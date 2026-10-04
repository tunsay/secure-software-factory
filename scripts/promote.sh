#!/usr/bin/env bash
# Promotion d'une version : écrit dans k8s/chart/values-dev.yaml les images publiées par la CI
# pour un commit, APRÈS avoir vérifié leur signature et leur SBOM avec la même règle que Kyverno.
# Usage : make promote SHA=<sha complet du commit>.
#
# Le script ne commite rien : déployer reste un geste humain (commit + push), et ArgoCD applique
# ensuite ce que le dépôt décrit. Il remplace la recopie à la main des digests depuis le résumé
# du job « images », source d'erreur.
set -euo pipefail
cd "$(dirname "$0")/.."

SHA="${1:-}"
if ! [[ "$SHA" =~ ^[0-9a-f]{40}$ ]]; then
  echo "usage : make promote SHA=<sha complet du commit, 40 caractères hexadécimaux>" >&2
  exit 1
fi

SIGNER="https://github.com/tunsay/secure-software-factory/.github/workflows/ci.yml@refs/heads/main"
ISSUER="https://token.actions.githubusercontent.com"
ACCEPT="application/vnd.oci.image.index.v1+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json"

declare -A DIGEST
for svc in api web; do
  repo="tunsay/ssf-$svc"
  token="$(curl -fsS "https://ghcr.io/token?scope=repository:$repo:pull" \
    | python3 -c 'import json, sys; print(json.load(sys.stdin)["token"])')"
  digest="$(curl -fsSI -H "Authorization: Bearer $token" -H "Accept: $ACCEPT" \
    "https://ghcr.io/v2/$repo/manifests/$SHA" | tr -d '\r' \
    | awk -F': ' 'tolower($1)=="docker-content-digest"{print $2}')"
  if ! [[ "$digest" =~ ^sha256:[0-9a-f]{64}$ ]]; then
    echo "ssf-$svc:$SHA introuvable dans le registre (CI pas terminée ?)" >&2
    exit 1
  fi
  # Même règle que Kyverno : signée par le workflow ci de ce dépôt, sur main, SBOM attesté.
  cosign verify --certificate-identity "$SIGNER" --certificate-oidc-issuer "$ISSUER" \
    "ghcr.io/$repo@$digest" >/dev/null 2>&1 \
    || { echo "ssf-$svc@$digest : signature invalide ou absente — rien n'est modifié" >&2; exit 1; }
  cosign verify-attestation --type cyclonedx --certificate-identity "$SIGNER" \
    --certificate-oidc-issuer "$ISSUER" "ghcr.io/$repo@$digest" >/dev/null 2>&1 \
    || { echo "ssf-$svc@$digest : SBOM signé absent — rien n'est modifié" >&2; exit 1; }
  echo "ssf-$svc : $digest — signature et SBOM vérifiés"
  DIGEST[$svc]="$digest"
done

python3 - "$SHA" "${DIGEST[api]}" "${DIGEST[web]}" <<'EOF'
import re
import sys
from pathlib import Path

sha, api, web = sys.argv[1:]
path = Path("k8s/chart/values-dev.yaml")
text = path.read_text(encoding="utf-8")
for pattern, value in (
    (r"(?m)^(  tag: )[0-9a-f]{40}$", sha),
    (r"(?m)^(    api: )sha256:[0-9a-f]{64}$", api),
    (r"(?m)^(    web: )sha256:[0-9a-f]{64}$", web),
):
    text, count = re.subn(pattern, lambda m, v=value: m.group(1) + v, text)
    if count != 1:
        sys.exit(f"values-dev.yaml : motif attendu une fois, trouvé {count} fois : {pattern}")
path.write_text(text, encoding="utf-8")
EOF

echo "k8s/chart/values-dev.yaml mis à jour pour $SHA — à relire, commiter et pousser."
