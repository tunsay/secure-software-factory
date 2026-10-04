#!/usr/bin/env bash
# Preuve du jalon 6a — l'application vue de l'extérieur, comme un visiteur ou un attaquant.
#
# Même commande avant et après (make dast). Deux parties :
#   1. ZAP « baseline » : explore le site et analyse passivement chaque réponse (en-têtes,
#      fuites d'information, cookies...). Rien n'est attaqué : c'est le scan qu'on peut lancer
#      sur n'importe quel environnement.
#   2. Quatre questions ciblées, dettes notées au jalon 1, que ZAP ne trouve pas seul (aucune
#      page n'y mène) : métriques internes, description de l'API, interface Swagger, et écho de
#      l'entrée dans les erreurs de validation.
# DAST_STRICT=1 (make dast-check, CI e2e) : échoue sur le moindre avertissement ZAP, ou sur une
# exposition.
#
# security/zap-rules.tsv : règles ZAP passées de WARN à IGNORE, chacune étant une dérogation
# justifiée et datée dans security/exceptions.yaml. Fichier en ASCII, au format attendu par ZAP.
set -uo pipefail
cd "$(dirname "$0")/.."

# ZAP 2.17.0, dernière version stable (décembre 2025), épinglée par digest comme toute image.
ZAP_IMAGE="ghcr.io/zaproxy/zaproxy:2.17.0@sha256:781a2bdaea47324e7bab583e2263f21d257b0aee61ed51521a5be45f5f5081ef"
# Traefik joint de l'intérieur du réseau Docker de kind : le même chemin que 127.0.0.1:8081.
TARGET="${DAST_TARGET:-http://ssf-dev-control-plane:30080}"
PUBLIC="${DAST_PUBLIC:-http://127.0.0.1:8081}"
STRICT="${DAST_STRICT:-0}"

echo "############ 1. ZAP baseline — analyse passive ############"
work="$(mktemp -d)"
chmod 777 "$work"   # ZAP écrit son rapport sous son propre utilisateur (UID 1000)
cp security/zap-rules.tsv "$work/"
flags=(-t "$TARGET" -c zap-rules.tsv -r zap-report.html)
[ "$STRICT" = 1 ] || flags+=(-I)   # hors mode strict : rapporter sans échouer
# DOCKER_CONFIG vide : tirage anonyme d'une image publique (contournement WSL, CLAUDE.md).
DOCKER_CONFIG="$(mktemp -d)" docker run --rm --network kind -v "$work:/zap/wrk:rw" "$ZAP_IMAGE" \
  zap-baseline.py "${flags[@]}"
zap_rc=$?
cp "$work/zap-report.html" ./zap-report.html 2>/dev/null && echo "(rapport détaillé : zap-report.html)"
rm -rf "$work"

echo
echo "############ 2. Expositions ciblées (dettes du jalon 1) ############"
exposed=0
check() { # libellé chemin
  local code
  code="$(curl -s -o /dev/null -w '%{http_code}' -m 5 "$PUBLIC$2")"
  if [ "$code" = 200 ]; then
    echo "EXPOSÉ   $1 — $2 → HTTP $code"
    exposed=1
  else
    echo "FERMÉ    $1 — $2 → HTTP $code"
  fi
}
check "métriques internes de l'API (Prometheus)  " /api/metrics
check "description complète de l'API (OpenAPI)   " /api/openapi.json
check "interface Swagger de l'API                " /api/docs

# Une quantité invalide contenant du HTML : l'erreur de validation renvoie-t-elle l'entrée ?
payload='<script>alert(1)</script>'
body="$(curl -s -m 5 -X POST "$PUBLIC/api/items" -H 'Content-Type: application/json' \
  -d "{\"name\":\"x\",\"quantity\":\"$payload\"}")"
if printf '%s' "$body" | grep -qF "$payload"; then
  echo "EXPOSÉ   erreur de validation : l'entrée est renvoyée telle quelle"
  exposed=1
else
  echo "FERMÉ    erreur de validation : l'entrée n'est pas renvoyée"
fi
echo "         réponse : $(printf '%s' "$body" | cut -c1-200)"

if [ "$STRICT" = 1 ]; then
  echo
  if [ "$zap_rc" = 0 ] && [ "$exposed" = 0 ]; then
    echo "DAST CONFORME"
  else
    echo "DAST NON CONFORME (code ZAP : $zap_rc ; exposition : $exposed)"
    exit 1
  fi
fi
