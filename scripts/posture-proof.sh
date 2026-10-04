#!/usr/bin/env bash
# Preuve du jalon 6b — que sait-on de la sécurité du cluster, sans le fouiller à la main ?
#
# Même commande avant et après l'observabilité (make posture-proof). Sept questions qu'un
# responsable sécurité se pose chaque matin. Chacune est une requête à Prometheus, passée par
# l'API Kubernetes (kubectl get --raw) : aucun port ouvert, aucun mot de passe. Sans Prometheus,
# personne ne peut y répondre, sinon en relançant des commandes au cas par cas.
#
# Compteurs lus en valeur cumulée (« depuis le démarrage ») et non en increase() : un compteur
# qui apparaît au premier refus ne montrerait aucune augmentation (piège classique de
# Prometheus : il n'a pas vu la valeur 0 avant).
set -uo pipefail

KUBECTL=(kubectl --kubeconfig "$HOME/.kube/ssf-dev" --context kind-ssf-dev)
PROM="/api/v1/namespaces/monitoring/services/http:prometheus-operated:9090/proxy/api/v1/query"

raw() { # requête PromQL → JSON brut de Prometheus
  local q
  q="$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "$1")"
  "${KUBECTL[@]}" get --raw "$PROM?query=$q" 2>/dev/null
}

query() { # requête PromQL → une ligne par série, « valeur  étiquettes »
  raw "$1" | python3 -c '
import json, sys
try:
    result = json.load(sys.stdin)["data"]["result"]
except (ValueError, KeyError):
    print("ERREUR   requête refusée par Prometheus")
    sys.exit()
if not result:
    print("0        (aucune série : rien de mesuré)")
for serie in result:
    labels = ", ".join(f"{k}={v}" for k, v in sorted(serie["metric"].items()) if k != "__name__")
    value = serie["value"][1]
    print(f"{value:<8} {labels}")
'
}

ask() { # libellé requête
  echo
  echo "== $1"
  if [ "$HAVE_PROM" = 1 ]; then
    query "$2" | sed 's/^/   /'
  else
    echo "   SANS RÉPONSE  aucune mesure collectée"
  fi
}

if "${KUBECTL[@]}" -n monitoring get svc prometheus-operated -o name >/dev/null 2>&1; then
  HAVE_PROM=1
  echo "== Prometheus présent : réponses mesurées"
  # Les premiers scans de trivy-operator prennent quelques minutes après son installation
  # (base de vulnérabilités, puis une image à la fois) : les attendre, au plus 6 minutes.
  for _ in $(seq 1 24); do
    n="$(raw 'count(trivy_image_vulnerabilities{namespace="ssf"})' \
         | python3 -c 'import json, sys; r = json.load(sys.stdin)["data"]["result"]; print(r[0]["value"][1] if r else 0)' 2>/dev/null)"
    [ "${n:-0}" != 0 ] && break
    echo "   (en attente des premiers scans de trivy-operator...)"
    sleep 15
  done
else
  HAVE_PROM=0
  echo "== Aucun Prometheus dans le cluster"
fi

ask "1. Requêtes refusées à l'admission par Kyverno, depuis son démarrage" \
  'sum(kyverno_admission_requests_total{request_allowed="false"})'
ask "2. L'application est-elle synchronisée avec le dépôt, et saine ?" \
  'max by (sync_status, health_status) (argocd_app_info{name="ssf"})'
ask "3. Vulnérabilités dans les images qui tournent dans ssf, par gravité" \
  'sum by (severity) (trivy_image_vulnerabilities{namespace="ssf"})'
ask "4. Défauts de configuration des objets de ssf, par gravité" \
  'sum by (severity) (trivy_resource_configaudits{namespace="ssf"})'
ask "5. Redémarrages de conteneurs dans ssf, dernière heure" \
  'sum(increase(kube_pod_container_status_restarts_total{namespace="ssf"}[1h]))'
ask "6. Réponses d'erreur (5xx) servies au public par Traefik, depuis son démarrage" \
  'sum(traefik_entrypoint_requests_total{entrypoint="web", code=~"5.."})'
ask "7. Alertes de sécurité en cours" \
  'count by (alertname) (ALERTS{alertstate="firing", famille="securite"})'
