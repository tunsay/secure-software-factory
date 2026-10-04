#!/usr/bin/env bash
# Attend qu'ArgoCD ait déployé l'application : synchronisée avec le dépôt (Synced) et saine
# (Healthy), puis que ses pods soient prêts. Appelé à la fin de make infra-up : depuis le
# jalon 5b, Terraform installe ArgoCD et l'Application, et ArgoCD déploie ensuite, seul, ce
# que décrit le dépôt. Sans cette attente, les preuves suivantes tourneraient dans le vide
# (leçon de J5-I2 : attendre l'état qu'on veut constater, pas un état voisin).
set -uo pipefail

KUBECTL=(kubectl --kubeconfig "$HOME/.kube/ssf-dev" --context kind-ssf-dev)
TIMEOUT="${APP_WAIT_TIMEOUT:-600}"

start=$(date +%s)
last=""
while :; do
  s="$("${KUBECTL[@]}" -n argocd get applications.argoproj.io ssf \
        -o jsonpath='{.status.sync.status}/{.status.health.status}' 2>/dev/null)"
  if [ "$s" != "$last" ]; then
    echo "ArgoCD, application ssf : ${s:-en attente du premier passage}"
    last="$s"
  fi
  [ "$s" = "Synced/Healthy" ] && break
  if [ $(( $(date +%s) - start )) -ge "$TIMEOUT" ]; then
    echo "ÉCHEC : application ssf ni synchronisée ni saine après ${TIMEOUT} s. État rapporté par ArgoCD :" >&2
    "${KUBECTL[@]}" -n argocd get applications.argoproj.io ssf -o jsonpath='{range .status.conditions[*]}{.type} : {.message}{"\n"}{end}{.status.operationState.phase} : {.status.operationState.message}{"\n"}' >&2 || true
    exit 1
  fi
  sleep 5
done

"${KUBECTL[@]}" -n ssf wait --for=condition=Ready pod -l app.kubernetes.io/name=ssf --timeout=180s
