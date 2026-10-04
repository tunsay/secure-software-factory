#!/usr/bin/env bash
# Attend qu'ArgoCD ait déployé l'application : synchronisée avec le dépôt (Synced) et saine
# (Healthy), puis que ses pods soient prêts. Appelé à la fin de make infra-up : depuis le
# jalon 5b, Terraform installe ArgoCD et l'Application, et ArgoCD déploie ensuite, seul, ce
# que décrit le dépôt. Sans cette attente, les preuves suivantes tourneraient dans le vide
# (leçon de J5-I2 : attendre l'état qu'on veut constater, pas un état voisin).
#
# APP_REVISION=<sha> (make app-wait REVISION=<sha>) : exige en plus que ce soit CE commit qui
# soit déployé, et demande à ArgoCD de relire le dépôt tout de suite plutôt qu'à son prochain
# passage (toutes les 2 à 3 minutes). Sans ça, « Synced » pourrait désigner la version d'avant.
set -uo pipefail

KUBECTL=(kubectl --kubeconfig "$HOME/.kube/ssf-dev" --context kind-ssf-dev)
TIMEOUT="${APP_WAIT_TIMEOUT:-600}"
WANT="${APP_REVISION:-}"

if [ -n "$WANT" ]; then
  "${KUBECTL[@]}" -n argocd annotate applications.argoproj.io ssf \
    argocd.argoproj.io/refresh=normal --overwrite >/dev/null
fi

start=$(date +%s)
last=""
while :; do
  s="$("${KUBECTL[@]}" -n argocd get applications.argoproj.io ssf \
        -o jsonpath='{.status.sync.status}/{.status.health.status}' 2>/dev/null)"
  rev="$("${KUBECTL[@]}" -n argocd get applications.argoproj.io ssf \
        -o jsonpath='{.status.sync.revision}' 2>/dev/null)"
  shown="$s${WANT:+ (révision ${rev:0:7})}"
  if [ "$shown" != "$last" ]; then
    echo "ArgoCD, application ssf : ${s:-en attente du premier passage}${WANT:+ — révision déployée ${rev:0:7}, attendue ${WANT:0:7}}"
    last="$shown"
  fi
  if [ "$s" = "Synced/Healthy" ] && { [ -z "$WANT" ] || [ "$rev" = "$WANT" ]; }; then
    break
  fi
  if [ $(( $(date +%s) - start )) -ge "$TIMEOUT" ]; then
    echo "ÉCHEC : application ssf pas déployée comme attendu après ${TIMEOUT} s. État rapporté par ArgoCD :" >&2
    "${KUBECTL[@]}" -n argocd get applications.argoproj.io ssf -o jsonpath='{range .status.conditions[*]}{.type} : {.message}{"\n"}{end}{.status.operationState.phase} : {.status.operationState.message}{"\n"}' >&2 || true
    exit 1
  fi
  sleep 5
done

# Attendre les Deployments, pas les pods : pendant un déploiement, un ancien pod listé au départ
# peut disparaître au milieu de l'attente, et kubectl wait échoue alors (NotFound, journal du
# jalon 6, J6-I1). « Healthy » pour ArgoCD veut déjà dire : nouvelle version entièrement prête.
"${KUBECTL[@]}" -n ssf wait --for=condition=Available deployment/api deployment/web --timeout=180s
