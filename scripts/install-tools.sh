#!/usr/bin/env bash
# Installe l'outillage du projet sous WSL2 Ubuntu 22.04.
# Idempotent : relançable sans risque. Docker Desktop reste côté Windows (intégration WSL activée).
set -euo pipefail

need_sudo() { if [[ $EUID -ne 0 ]]; then echo sudo; fi; }
SUDO=$(need_sudo)

ARCH=$(dpkg --print-architecture) # amd64

# unattended-upgrades tient parfois le verrou dpkg au démarrage de WSL : on attend qu'il le lâche.
wait_dpkg() {
  local i=0
  while $SUDO fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
    if [[ $i -eq 0 ]]; then echo "    verrou dpkg tenu par unattended-upgrades, attente..."; fi
    sleep 3
    i=$((i + 1))   # jamais (( i++ )) sous set -e : renvoie 1 quand i vaut 0
    if [[ $i -gt 100 ]]; then echo "verrou dpkg toujours tenu après 5 min"; exit 1; fi
  done
}

echo "==> apt de base"
wait_dpkg
$SUDO apt-get update -qq
$SUDO apt-get install -y -qq curl gnupg lsb-release unzip make jq python3-pip python3-venv >/dev/null

echo "==> Terraform (dépôt HashiCorp)"
if ! command -v terraform >/dev/null; then
  curl -fsSL https://apt.releases.hashicorp.com/gpg | $SUDO gpg --dearmor -o /usr/share/keyrings/hashicorp.gpg
  echo "deb [signed-by=/usr/share/keyrings/hashicorp.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
    | $SUDO tee /etc/apt/sources.list.d/hashicorp.list >/dev/null
  $SUDO apt-get update -qq && $SUDO apt-get install -y -qq terraform >/dev/null
fi

echo "==> kubectl"
if ! command -v kubectl >/dev/null; then
  KVER=$(curl -fsSL https://dl.k8s.io/release/stable.txt)
  curl -fsSLo /tmp/kubectl "https://dl.k8s.io/release/${KVER}/bin/linux/${ARCH}/kubectl"
  $SUDO install -m 0755 /tmp/kubectl /usr/local/bin/kubectl
fi

echo "==> kind"
if ! command -v kind >/dev/null; then
  KIND_VER=$(curl -fsSL https://api.github.com/repos/kubernetes-sigs/kind/releases/latest | jq -r .tag_name)
  curl -fsSLo /tmp/kind "https://kind.sigs.k8s.io/dl/${KIND_VER}/kind-linux-${ARCH}"
  $SUDO install -m 0755 /tmp/kind /usr/local/bin/kind
fi

echo "==> Helm"
if ! command -v helm >/dev/null; then
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | $SUDO bash >/dev/null
fi

echo "==> Trivy"
if ! command -v trivy >/dev/null; then
  curl -fsSL https://aquasecurity.github.io/trivy-repo/deb/public.key | $SUDO gpg --dearmor -o /usr/share/keyrings/trivy.gpg
  echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb generic main" \
    | $SUDO tee /etc/apt/sources.list.d/trivy.list >/dev/null
  $SUDO apt-get update -qq && $SUDO apt-get install -y -qq trivy >/dev/null
fi

echo "==> gitleaks"
if ! command -v gitleaks >/dev/null; then
  GL_VER=$(curl -fsSL https://api.github.com/repos/gitleaks/gitleaks/releases/latest | jq -r '.tag_name | ltrimstr("v")')
  curl -fsSL "https://github.com/gitleaks/gitleaks/releases/download/v${GL_VER}/gitleaks_${GL_VER}_linux_x64.tar.gz" \
    | $SUDO tar -xz -C /usr/local/bin gitleaks
fi

echo "==> syft (SBOM) + cosign (signature) — utilisés à partir de S4"
if ! command -v syft >/dev/null; then
  curl -fsSL https://raw.githubusercontent.com/anchore/syft/main/install.sh | $SUDO sh -s -- -b /usr/local/bin >/dev/null
fi
if ! command -v cosign >/dev/null; then
  curl -fsSLo /tmp/cosign "https://github.com/sigstore/cosign/releases/latest/download/cosign-linux-${ARCH}"
  $SUDO install -m 0755 /tmp/cosign /usr/local/bin/cosign
fi

echo "==> pre-commit"
pip3 install --user -q --no-warn-script-location pre-commit
# pip --user installe dans ~/.local/bin : on l'ajoute au PATH si absent.
if ! grep -q 'HOME/.local/bin' "$HOME/.bashrc" 2>/dev/null; then
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
fi
export PATH="$HOME/.local/bin:$PATH"

echo
echo "Versions installées :"
set +e  # à partir d'ici, un outil absent ne doit pas interrompre le récapitulatif
ver() {
  case "$1" in
    kubectl)    kubectl version --client 2>/dev/null | head -1 ;;
    terraform)  terraform version 2>/dev/null | head -1 ;;
    helm)       helm version --short 2>/dev/null ;;
    cosign)     cosign version 2>/dev/null | grep -i gitversion ;;
    docker)     docker --version 2>/dev/null ;;
    *)          "$1" version 2>/dev/null | head -1 || "$1" --version 2>/dev/null | head -1 ;;
  esac
}
for t in terraform kubectl kind helm trivy gitleaks syft cosign pre-commit docker; do
  printf "  %-11s " "$t"
  if command -v "$t" >/dev/null 2>&1; then v=$(ver "$t"); echo "${v:-installé}"; else echo "ABSENT"; fi
done
echo
echo "Si 'docker' est ABSENT : Docker Desktop → Settings → Resources → WSL integration → activer Ubuntu-22.04."
echo "Ouvre un nouveau terminal (ou 'source ~/.bashrc') pour que pre-commit soit dans le PATH."
