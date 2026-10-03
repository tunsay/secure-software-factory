#!/usr/bin/env bash
# Preuve du jalon 4 — ce qui tourne est-il signé, décrit et figé ?
#
# Même commande avant et après durcissement (make supply-chain-proof), comme isolation-proof au
# jalon 3. Lecture seule : rien n'est poussé, signé ni modifié. Chaque test affiche son verdict
# en début de ligne puis le détail ; aucun test n'interrompt les suivants.
set -uo pipefail

cd "$(dirname "$0")/.."

KUBECTL=(kubectl --kubeconfig "$HOME/.kube/ssf-dev" --context kind-ssf-dev)
REGISTRY="ghcr.io/tunsay"
ISSUER="https://token.actions.githubusercontent.com"
# Seule identité autorisée à signer : le workflow ci de ce dépôt, exécuté sur main.
SIGNER="https://github.com/tunsay/secure-software-factory/.github/workflows/ci.yml@refs/heads/main"
# Une autre identité du même dépôt : une signature valide ne doit pas suffire, il faut la bonne.
OTHER_SIGNER="https://github.com/tunsay/secure-software-factory/.github/workflows/e2e.yml@refs/heads/main"
# Image publiée avant le jalon 4, jamais signée : témoin de refus.
UNSIGNED="$REGISTRY/ssf-api:8a5d1dc21ae57640f61dd66d470ad5a37470d208"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Dernière ligne non vide de l'erreur de cosign : la raison du refus, sans le bruit.
reason() { grep -v '^[[:space:]]*$' "$TMP/err" | tail -1; }

signed_by() { # image identité -> code retour 0 si une signature valide de cette identité existe
  cosign verify --certificate-identity "$2" --certificate-oidc-issuer "$ISSUER" "$1" \
    >/dev/null 2>"$TMP/err"
}

echo "cosign : $(cosign version 2>/dev/null | sed -n 's/^GitVersion:[[:space:]]*//p')"

echo
echo "############ CE QUI EST DÉPLOYÉ ############"
for c in api web; do
  img="$("${KUBECTL[@]}" -n ssf get deploy "$c" -o jsonpath='{.spec.template.spec.containers[0].image}')"
  echo
  echo "== $c : $img"

  echo "-- signée par le workflow ci de ce dépôt, sur main ?"
  if signed_by "$img" "$SIGNER"; then
    echo "OUI      signature valide, identité vérifiée"
  else
    echo "NON      $(reason)"
  fi

  echo "-- SBOM CycloneDX signé, attaché à l'image ?"
  if cosign verify-attestation --type cyclonedx --certificate-identity "$SIGNER" \
       --certificate-oidc-issuer "$ISSUER" "$img" >"$TMP/att" 2>"$TMP/err"; then
    n="$(python3 - "$TMP/att" <<'PY'
import base64, json, sys
n = 0
for line in open(sys.argv[1], encoding="utf-8"):
    if line.strip():
        statement = json.loads(base64.b64decode(json.loads(line)["payload"]))
        n = max(n, len(statement.get("predicate", {}).get("components", [])))
print(n)
PY
)"
    echo "OUI      $n composants décrits"
  else
    echo "NON      $(reason)"
  fi

  echo "-- référence immuable (digest) ?"
  case "$img" in
    *@sha256:*) echo "OUI      épinglée par digest : le contenu ne peut pas changer" ;;
    *)          echo "NON      tag seul : ce qu'il désigne peut être remplacé dans le registre" ;;
  esac
done

echo
echo "############ LA VÉRIFICATION FAIT-ELLE LA DIFFÉRENCE ? ############"
echo
echo "== image d'avant le jalon 4, jamais signée (doit être REFUSÉE)"
if signed_by "$UNSIGNED" "$SIGNER"; then
  echo "ACCEPTÉE (anormal)"
else
  echo "REFUSÉE  $(reason)"
fi

echo
echo "== image api déployée, en exigeant une autre identité, le workflow e2e (doit être REFUSÉE)"
api_img="$("${KUBECTL[@]}" -n ssf get deploy api -o jsonpath='{.spec.template.spec.containers[0].image}')"
if signed_by "$api_img" "$OTHER_SIGNER"; then
  echo "ACCEPTÉE (anormal)"
else
  echo "REFUSÉE  $(reason)"
fi

echo
echo "############ CE QUI ENTRE DANS LE BUILD ############"
echo
echo "== images de base épinglées par digest"
total="$(grep -h '^FROM' app/*/Dockerfile | wc -l)"
pinned="$(grep -h '^FROM' app/*/Dockerfile | grep -c '@sha256:')"
echo "$pinned/$total"
grep -h '^FROM' app/*/Dockerfile | sed 's/^/         /'

echo
echo "== dépendances Python vérifiées par empreinte (--require-hashes)"
hashes="$(grep -c -- '--hash=sha256:' app/api/requirements.txt)"
if [ "$hashes" -gt 0 ]; then
  echo "OUI      $hashes empreintes dans app/api/requirements.txt"
else
  echo "NON      aucune empreinte : pip installe ce que l'index lui sert"
fi

echo
echo "== dérogations de sécurité expirées détectées (security/exceptions.yaml)"
if [ -f scripts/check-exceptions.py ]; then
  if python3 scripts/check-exceptions.py >"$TMP/exc" 2>&1; then
    echo "OUI      contrôle en place : $(tail -1 "$TMP/exc")"
  else
    echo "OUI      contrôle en place, et il échoue : $(tail -1 "$TMP/exc")"
  fi
else
  echo "NON      aucun contrôle : une dérogation expirée reste active indéfiniment"
fi
