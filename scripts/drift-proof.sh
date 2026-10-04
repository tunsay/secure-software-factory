#!/usr/bin/env bash
# Preuve du jalon 5b — que devient une modification manuelle de l'application dans le cluster ?
#
# Même commande avant et après ArgoCD (make drift-proof). Cinq dérives, faites à la main comme
# le ferait un opérateur pressé ou un attaquant qui a obtenu un accès kubectl au namespace ssf ;
# puis on observe pendant DRIFT_WAIT secondes si le cluster revient seul à l'état du dépôt.
#   1 à 3 : ce que le dépôt décrit (une valeur, un nombre de répliques, un objet).
#   4 et 5 : ce que le dépôt ne décrit pas (un champ ajouté, un objet étranger).
# Puis, si ArgoCD est installé : ce que son contrôleur a le droit de faire (moindre privilège).
# Le script mesure sans prendre parti ; l'interprétation va au journal du jalon 5.
# DRIFT_STRICT=1 (make drift-check, CI e2e) : échoue si une dérive 1 à 3 persiste, ou si un
# droit d'ArgoCD diffère de l'attendu.
set -uo pipefail

KUBECTL=(kubectl --kubeconfig "$HOME/.kube/ssf-dev" --context kind-ssf-dev)
K=("${KUBECTL[@]}" -n ssf)
WAIT="${DRIFT_WAIT:-60}"
STRICT="${DRIFT_STRICT:-0}"

app_env()   { "${K[@]}" get deploy api -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="APP_ENV")].value}' 2>/dev/null; }
drift_env() { "${K[@]}" get deploy api -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="DRIFT")].value}' 2>/dev/null; }
web_reps()  { "${K[@]}" get deploy web -o jsonpath='{.spec.replicas}' 2>/dev/null; }
has()       { "${K[@]}" get "$1" -o name >/dev/null 2>&1; }
state() {
  echo "   APP_ENV de l'API = '$(app_env)' ; variable DRIFT = '$(drift_env)' ; front : $(web_reps) répliques"
  echo "   service api : $(has svc/api && echo présent || echo absent) ; ConfigMap intrus : $(has configmap/intrus && echo présente || echo absente)"
}

if "${KUBECTL[@]}" -n argocd get applications.argoproj.io ssf -o name >/dev/null 2>&1; then
  ARGOCD=1
  echo "== Application gérée par ArgoCD (synchronisation automatique depuis le dépôt)"
else
  ARGOCD=0
  echo "== Application gérée par Terraform (helm_release, appliqué à la main)"
fi

echo
echo "== État de départ"
state

echo
echo "== Dérives manuelles"
"${K[@]}" set env deploy/api APP_ENV=prod DRIFT=manuel >/dev/null \
  && echo "   1. APP_ENV de l'API passé de dev à prod                (décrit dans le dépôt)" \
  && echo "   4. variable DRIFT ajoutée à l'API                       (non décrite)"
"${K[@]}" scale deploy/web --replicas=0 >/dev/null \
  && echo "   2. front réduit à 0 réplique                            (décrit dans le dépôt)"
"${K[@]}" delete svc api --wait=false >/dev/null \
  && echo "   3. service de l'API supprimé                            (décrit dans le dépôt)"
"${K[@]}" create configmap intrus --from-literal=origine=manuelle >/dev/null \
  && echo "   5. ConfigMap « intrus » créée dans le namespace         (non décrite)"

echo
echo "== Observation pendant ${WAIT} s"
r1=""; r2=""; r3=""; r4=""; r5=""
start=$(date +%s)
while :; do
  t=$(( $(date +%s) - start ))
  [ -z "$r1" ] && [ "$(app_env)" = "dev" ] && r1="$t"
  [ -z "$r2" ] && [ -n "$(web_reps)" ] && [ "$(web_reps)" != "0" ] && r2="$t"
  [ -z "$r3" ] && has svc/api && r3="$t"
  [ -z "$r4" ] && [ -z "$(drift_env)" ] && r4="$t"
  [ -z "$r5" ] && ! has configmap/intrus && r5="$t"
  { [ -n "$r1" ] && [ -n "$r2" ] && [ -n "$r3" ] && [ -n "$r4" ] && [ -n "$r5" ]; } && break
  [ "$t" -ge "$WAIT" ] && break
  sleep 2
done

verdict() { # temps libellé
  if [ -n "$1" ]; then echo "ANNULÉE      après ~$1 s — $2"; else echo "PERSISTANTE  après ${WAIT} s — $2"; fi
}
verdict "$r1" "1. APP_ENV de l'API modifié"
verdict "$r2" "2. front à 0 réplique"
verdict "$r3" "3. service de l'API supprimé"
verdict "$r4" "4. variable DRIFT ajoutée"
verdict "$r5" "5. ConfigMap intrus"

echo
echo "== État final"
state

# Nettoyage de ce que le dépôt ne décrit pas (4 et 5), pour ne rien laisser d'étranger dans le
# namespace. Les dérives 1 à 3 restent en l'état : c'est ce que la preuve montre.
[ -n "$(drift_env)" ] && "${K[@]}" set env deploy/api DRIFT- >/dev/null
has configmap/intrus && "${K[@]}" delete configmap intrus >/dev/null
echo "   (nettoyé : variable DRIFT et ConfigMap intrus)"

if [ -z "$r1" ] || [ -z "$r2" ] || [ -z "$r3" ]; then
  echo
  echo "Réparation manuelle des dérives 1 à 3 (ce que fait ArgoCD seul, après le jalon 5b) :"
  echo "  helm --kube-context kind-ssf-dev --kubeconfig ~/.kube/ssf-dev -n ssf get manifest ssf | ${KUBECTL[*]} -n ssf apply -f -"
fi

# Droits du contrôleur d'ArgoCD : par défaut, le chart lui donne « * » sur « * » dans tout le
# cluster. Ici, il ne doit pouvoir écrire que les objets du chart applicatif, dans ssf.
rights_ok=1
echo
echo "== Ce que le contrôleur d'ArgoCD a le droit de faire"
if [ "$ARGOCD" = 1 ]; then
  SA=system:serviceaccount:argocd:argocd-application-controller
  can() { # attendu libellé verbe ressource [options kubectl]
    local expected="$1" label="$2"; shift 2
    local got
    got="$("${KUBECTL[@]}" auth can-i "$@" --as="$SA" 2>/dev/null)"
    [ "$got" = "$expected" ] || rights_ok=0
    printf '   %-52s : %s\n' "$label" "${got:-?}"
  }
  can yes "modifier les Deployments de ssf"            patch deployments -n ssf
  can no  "lire les Secrets de ssf"                     get secrets -n ssf
  can no  "supprimer les NetworkPolicies de ssf"        delete networkpolicies -n ssf
  can no  "se donner des droits dans ssf (RoleBinding)" create rolebindings -n ssf
  can no  "créer un Deployment dans kube-system"        create deployments -n kube-system
  can no  "se donner des droits sur le cluster"         create clusterrolebindings
else
  echo "   ArgoCD absent : rien à vérifier"
fi

if [ "$STRICT" = 1 ]; then
  echo
  if [ "$ARGOCD" = 1 ] && [ -n "$r1" ] && [ -n "$r2" ] && [ -n "$r3" ] && [ "$rights_ok" = 1 ]; then
    echo "DÉRIVE CONFORME : dérives décrites annulées, droits d'ArgoCD bornés à ssf"
  else
    echo "DÉRIVE NON CONFORME : ArgoCD absent, dérive décrite persistante, ou droits inattendus"
    exit 1
  fi
fi
