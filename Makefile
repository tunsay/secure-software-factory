# Secure Software Factory — point d'entrée unique.
# Cible : bash sous WSL2 (Ubuntu). Docker Desktop doit être lancé côté Windows.

SHELL := /bin/bash
.DEFAULT_GOAL := help

COMPOSE := docker compose
API_IMG := ssf-api:local
WEB_IMG := ssf-web:local

# Outils Python de dev dans un venv local au projet (jamais en global).
VENV := app/api/.venv
PY   := $(VENV)/bin/python
export PATH := $(CURDIR)/$(VENV)/bin:$(PATH)

TF_CLUSTER  := infra/terraform/cluster
TF_PLATFORM := infra/terraform/platform
KUBECONFIG_SSF := $(HOME)/.kube/ssf-dev
KUBECTL := kubectl --kubeconfig $(KUBECONFIG_SSF) --context kind-ssf-dev

.PHONY: help setup up down logs build test lint semgrep scan scan-image sbom clean install-tools \
        infra-up infra-plan infra-down infra-lint infra-proof attack-escape

help: ## Affiche cette aide
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

setup: $(VENV)/.stamp app/web/node_modules/.stamp ## Installe les dépendances de dev (venv Python + npm)

$(VENV)/.stamp: app/api/requirements-dev.txt
	python3 -m venv $(VENV)
	$(PY) -m pip install -q --upgrade pip
	$(PY) -m pip install -q -r app/api/requirements-dev.txt
	@touch $@

app/web/node_modules/.stamp: app/web/package-lock.json
	cd app/web && npm ci --no-audit --no-fund
	@touch $@

up: ## Build + lance web et api (http://localhost:8080, :8000)
	$(COMPOSE) up --build -d
	@echo "web  → http://localhost:8080"
	@echo "api  → http://localhost:8000/docs"

down: ## Arrête et supprime les conteneurs
	$(COMPOSE) down --remove-orphans

logs: ## Suit les logs
	$(COMPOSE) logs -f

build: ## Build les deux images sans les lancer
	docker build -t $(API_IMG) app/api
	docker build -t $(WEB_IMG) app/web

test: setup ## Tests unitaires API
	cd app/api && python -m pytest -q

lint: setup ## Lint + SAST locaux (ruff, bandit, eslint)
	cd app/api && ruff check . && ruff format --check . && bandit -q -r app -c pyproject.toml
	cd app/web && npm run lint

scan: lint semgrep scan-image ## Rejoue les contrôles CI en local
	cd app/api && pip-audit -r requirements.txt --strict
	cd app/web && npm audit --audit-level=high
	gitleaks dir . --no-banner --redact
	@if [ -d .git ]; then gitleaks git . --no-banner --redact; else echo "gitleaks git : pas de dépôt, historique non scanné"; fi

semgrep: ## SAST multi-langage, même image et mêmes règles que la CI
	docker run --rm -v "$(CURDIR):/src" -w /src semgrep/semgrep \
	  semgrep scan --config p/owasp-top-ten --config p/secrets --error --metrics=off --quiet

scan-image: build ## Scan Trivy des images (bloque sur HIGH/CRITICAL)
	trivy image --severity HIGH,CRITICAL --exit-code 1 --ignore-unfixed $(API_IMG)
	trivy image --severity HIGH,CRITICAL --exit-code 1 --ignore-unfixed $(WEB_IMG)

sbom: build ## SBOM CycloneDX des images (S4)
	mkdir -p security/sbom
	syft $(API_IMG) -o cyclonedx-json > security/sbom/api.cdx.json
	syft $(WEB_IMG) -o cyclonedx-json > security/sbom/web.cdx.json

clean: down ## Supprime images locales
	-docker rmi $(API_IMG) $(WEB_IMG)

install-tools: ## Installe l'outillage sous WSL (terraform, kubectl, kind, helm, trivy, ...)
	bash scripts/install-tools.sh

# ---------------------------------------------------------------------------
# Infrastructure : Terraform → kind (couche cluster) puis config (couche platform)
# ---------------------------------------------------------------------------

infra-up: ## Crée le cluster kind puis applique la couche platform (demande confirmation)
	cd $(TF_CLUSTER) && terraform init -input=false && terraform apply -input=false
	@# Le namespace de l'état distant est le seul objet créé hors Terraform : il doit exister avant l'init.
	$(KUBECTL) create namespace terraform-state --dry-run=client -o yaml | $(KUBECTL) apply -f -
	cd $(TF_PLATFORM) && terraform init -input=false -backend-config="config_path=$(KUBECONFIG_SSF)" \
	  && terraform apply -input=false -var-file=dev.tfvars

infra-plan: ## Plan de la couche platform, sans appliquer
	cd $(TF_PLATFORM) && terraform plan -input=false -var-file=dev.tfvars

infra-down: ## Détruit platform puis le cluster (demande confirmation)
	-cd $(TF_PLATFORM) && terraform destroy -input=false -var-file=dev.tfvars
	cd $(TF_CLUSTER) && terraform destroy -input=false

infra-lint: ## fmt, validate, checkov, trivy config — ce que la CI exécute sur le code Terraform
	terraform fmt -check -recursive -diff infra/terraform
	@for d in cluster platform modules/namespace; do \
	  echo "== validate $$d"; \
	  (cd infra/terraform/$$d && terraform init -backend=false -input=false >/dev/null && terraform validate) || exit 1; \
	done
	docker run --rm -v "$(CURDIR):/src" -w /src bridgecrew/checkov -d infra/terraform --framework terraform --quiet --compact
	trivy config --exit-code 1 --severity HIGH,CRITICAL infra/terraform

attack-escape: ## Démo : évasion hostPath réussie dans 'default', refusée dans 'ssf' (durci par Terraform)
	@echo "############################################################"
	@echo "# 1) default — namespace SANS durcissement Terraform"
	@echo "############################################################"
	$(KUBECTL) apply -n default -f security/attacks/hostpath-escape.yaml
	$(KUBECTL) -n default wait --for=condition=Ready pod/node-pwn --timeout=60s
	@echo; echo ">> Lecture du /etc/shadow du NŒUD depuis le conteneur (3 lignes) :"
	$(KUBECTL) -n default exec node-pwn -- sh -c 'head -3 /host/etc/shadow'
	@echo; echo ">> Processus du nœud visibles depuis le pod (hostPID) :"
	$(KUBECTL) -n default exec node-pwn -- sh -c 'ps -o pid,args | grep -m1 kubelet'
	$(KUBECTL) delete -n default -f security/attacks/hostpath-escape.yaml
	@echo; echo "############################################################"
	@echo "# 2) ssf — namespace durci par Terraform (PSS restricted)"
	@echo "############################################################"
	@echo ">> Même manifeste, il doit être REFUSÉ à l'admission :"
	-$(KUBECTL) apply -n ssf -f security/attacks/hostpath-escape.yaml
	@echo; echo ">> Aucun pod node-pwn dans ssf :"
	$(KUBECTL) -n ssf get pod node-pwn 2>&1 || true

infra-proof: ## Preuve PSS : un pod root doit être refusé à l'admission dans le namespace ssf
	$(KUBECTL) get namespaces ssf security --show-labels
	@echo; echo "== Tentative de pod root sans securityContext dans ssf (doit être REFUSÉE) :"
	-$(KUBECTL) -n ssf run pss-probe --image=busybox:1.37 --restart=Never --command -- sleep 5
	@echo; echo "== Quota et limites du namespace :"
	$(KUBECTL) -n ssf describe quota quota | sed -n '1,12p'
