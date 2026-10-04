#!/usr/bin/env bash
# Preuve du jalon 6b — que sait-on de la sécurité du cluster, sans le fouiller à la main ?
#
# Même commande avant et après l'observabilité (make posture-proof). Sept questions qu'un
# responsable sécurité se pose chaque matin. Chacune est une requête à Prometheus, passée par
# l'API Kubernetes (kubectl get --raw) : aucun port ouvert, aucun mot de passe. Sans Prometheus,
# personne ne peut y répondre, sinon en relançant des commandes au cas par cas.
set -uo pipefail

KUBECTL=(kubectl --kubeconfig "$HOME/.kube/ssf-dev" --context kind-ssf-dev)
PROM="/api/v1/namespaces/monitoring/services/http:prometheus-operated:9090/proxy/api/v1/query"

query() { # requête PromQL → une ligne par série, « étiquettes : valeur »
  local q
  q="$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "$1")"
  "${KUBECTL[@]}" get --raw "$PROM?query=$q" 2>/dev/null | python3 -c '
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
else
  HAVE_PROM=0
  echo "== Aucun Prometheus dans le cluster"
fi

ask "1. Requêtes refusées à l'admission par Kyverno, dernière heure" \
  'sum(increase(kyverno_admission_requests_total{request_allowed="false"}[1h]))'
ask "2. L'application est-elle synchronisée avec le dépôt, et saine ?" \
  'max by (sync_status, health_status) (argocd_app_info{name="ssf"})'
ask "3. Vulnérabilités dans les images qui tournent dans ssf, par gravité" \
  'sum by (severity) (trivy_image_vulnerabilities{namespace="ssf"})'
ask "4. Défauts de configuration des workloads de ssf, par gravité" \
  'sum by (severity) (trivy_resource_configaudits{namespace="ssf"})'
ask "5. Redémarrages de conteneurs dans ssf, dernière heure" \
  'sum(increase(kube_pod_container_status_restarts_total{namespace="ssf"}[1h]))'
ask "6. Réponses d'erreur (5xx) servies au public par Traefik, dernière heure" \
  'sum(increase(traefik_service_requests_total{code=~"5.."}[1h]))'
ask "7. Alertes de sécurité en cours" \
  'count by (alertname) (ALERTS{alertstate="firing", famille="securite"})'
