#!/usr/bin/env bash
# Preuve du jalon 5a — qu'est-ce que le cluster accepte de faire tourner ?
#
# Même commande avant et après Kyverno (make admission-proof). Chaque test soumet un pod au
# cluster en « dry-run=server » : toute la chaîne d'admission s'exécute (Pod Security Standards,
# quotas, webhooks Kyverno), mais RIEN n'est créé. Le pod de test respecte PSS restricted : seule
# l'image fait la différence entre deux tests.
set -uo pipefail

cd "$(dirname "$0")/.."

KUBECTL=(kubectl --kubeconfig "$HOME/.kube/ssf-dev" --context kind-ssf-dev)
NS=ssf

# Images de contrôle. La première est celle que la CI a signée et que le cluster fait tourner.
DEPLOYED="$("${KUBECTL[@]}" -n "$NS" get deploy api -o jsonpath='{.spec.template.spec.containers[0].image}')"
UNSIGNED_TAG="ghcr.io/tunsay/ssf-api:8a5d1dc21ae57640f61dd66d470ad5a37470d208"   # publiée avant le jalon 4, jamais signée
UNSIGNED_DIGEST="ghcr.io/tunsay/ssf-api@sha256:95dc3cb01a95f49d0515385d9a11cbffd5e38be22385e7de6b9ac345a106a038"
OTHER_REGISTRY="docker.io/library/busybox:1.37@sha256:bdf57e528e45e4433820e045b29b4597825a1c9e38353532d90a01445013f82e"
LATEST="ghcr.io/tunsay/ssf-api:latest"   # n'existe pas sur GHCR (404) : on teste la règle, pas le tirage

probe() { # libellé image attendu-après
  echo
  echo "== $1"
  echo "   $2"
  if "${KUBECTL[@]}" apply --dry-run=server -f - >/dev/null 2>"$TMP_ERR" <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: admission-probe
  namespace: $NS
spec:
  automountServiceAccountToken: false
  securityContext:
    runAsNonRoot: true
    runAsUser: 10001
    runAsGroup: 10001
    seccompProfile: { type: RuntimeDefault }
  containers:
    - name: probe
      image: $2
      securityContext:
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        capabilities: { drop: ["ALL"] }
      resources:
        requests: { cpu: 10m, memory: 16Mi }
        limits: { cpu: 50m, memory: 32Mi }
EOF
  then
    echo "ADMISE   (après Kyverno : $3)"
  else
    echo "REFUSÉE  $(grep -v '^[[:space:]]*$' "$TMP_ERR" | tail -1 | cut -c1-300)"
  fi
}

TMP_ERR="$(mktemp)"
trap 'rm -f "$TMP_ERR"' EXIT

probe "image signée par la CI, par digest — celle qui tourne" "$DEPLOYED"        "ADMISE"
probe "image jamais signée, par tag"                            "$UNSIGNED_TAG"    "REFUSÉE"
probe "image jamais signée, par digest"                         "$UNSIGNED_DIGEST" "REFUSÉE"
probe "image d'un autre registre (Docker Hub), par digest"      "$OTHER_REGISTRY"  "REFUSÉE"
probe "tag latest de notre registre"                            "$LATEST"          "REFUSÉE"
