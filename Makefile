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
# État de la couche cluster : contient la clé privée administrateur du cluster, donc hors du dépôt
# (journal jalon 4, J4-I6), dans le dossier personnel WSL, lisible par le seul utilisateur.
TF_CLUSTER_STATE_DIR := $(HOME)/.local/state/ssf
TF_CLUSTER_STATE     := $(TF_CLUSTER_STATE_DIR)/cluster.tfstate
KUBECTL := kubectl --kubeconfig $(KUBECONFIG_SSF) --context kind-ssf-dev

# Chart de l'app et valeurs de l'environnement : exactement ce qu'ArgoCD déploie (jalon 5b).
CHART        := k8s/chart
CHART_VALUES := $(CHART)/values-dev.yaml

.PHONY: help setup up down logs build test lint semgrep scan scan-image sbom clean install-tools \
        infra-up infra-plan infra-down infra-lint infra-proof attack-escape chart-lint app-proof isolation-proof isolation-check supply-chain-proof admission-proof drift-proof \
        drift-check app-wait dast dast-check promote posture-proof

help: ## Affiche cette aide
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

setup: $(VENV)/.stamp app/web/node_modules/.stamp ## Installe les dépendances de dev (venv Python + npm)

# Poste : le python3 de WSL est en 3.10, l'image et la CI en 3.14. requirements.txt (empreintes)
# est résolu pour 3.14 et ne s'installe pas en 3.10 (dépendances conditionnelles différentes) :
# le venv local part de requirements.in, sans empreintes. Il sert aux tests et au lint ; la
# chaîne qui mène à la production (image, CI) vérifie les empreintes (journal jalon 4, J4-I2).
$(VENV)/.stamp: app/api/requirements.in app/api/requirements-dev.txt
	python3 -m venv $(VENV)
	$(PY) -m pip install -q --upgrade pip
	$(PY) -m pip install -q -r app/api/requirements.in -r app/api/requirements-dev.txt
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
	cd app/api && pip-audit -r requirements.txt --require-hashes --disable-pip --strict
	cd app/web && npm audit --audit-level=high
	python3 scripts/check-exceptions.py
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

# Vide en local : chaque apply affiche son plan et attend « yes ». La CI e2e passe -auto-approve,
# sur un cluster éphémère : même cible, même code, seule la confirmation change.
TF_APPLY_FLAGS ?=
# Variables propres à la couche platform. Vide en local : ArgoCD suit main. La CI e2e passe le
# commit testé : TF_PLATFORM_VARS=-var=argocd_revision=<sha>.
TF_PLATFORM_VARS ?=

infra-up: ## Crée le cluster kind, applique la couche platform, attend qu'ArgoCD ait déployé l'app
	mkdir -p -m 700 $(TF_CLUSTER_STATE_DIR)
	cd $(TF_CLUSTER) && terraform init -input=false -backend-config="path=$(TF_CLUSTER_STATE)" \
	  && terraform apply -input=false $(TF_APPLY_FLAGS)
	@# Le namespace de l'état distant est le seul objet créé hors Terraform : il doit exister avant l'init.
	$(KUBECTL) create namespace terraform-state --dry-run=client -o yaml | $(KUBECTL) apply -f -
	cd $(TF_PLATFORM) && terraform init -input=false -backend-config="config_path=$(KUBECONFIG_SSF)" \
	  && terraform apply -input=false -var-file=dev.tfvars $(TF_PLATFORM_VARS) $(TF_APPLY_FLAGS)
	@# Depuis le jalon 5b, l'application est déployée par ArgoCD, après Terraform : on l'attend.
	@$(MAKE) --no-print-directory app-wait

infra-plan: ## Plan de la couche platform, sans appliquer
	cd $(TF_PLATFORM) && terraform plan -input=false -var-file=dev.tfvars $(TF_PLATFORM_VARS)

infra-down: ## Détruit platform puis le cluster (demande confirmation)
	-cd $(TF_PLATFORM) && terraform destroy -input=false -var-file=dev.tfvars $(TF_PLATFORM_VARS)
	cd $(TF_CLUSTER) && terraform destroy -input=false

chart-lint: ## Lint et rendu des charts Helm (application, politiques, ArgoCD, monitoring), scan trivy des manifests rendus
	helm lint $(CHART) --strict -f $(CHART_VALUES)
	helm template ssf $(CHART) -f $(CHART_VALUES) > /dev/null
	trivy config --exit-code 1 --severity HIGH,CRITICAL --helm-values $(CHART_VALUES) $(CHART)
	helm lint k8s/policies --strict
	helm template ssf-policies k8s/policies > /dev/null
	helm lint k8s/argocd --strict
	helm template ssf-argocd k8s/argocd > /dev/null
	helm lint k8s/monitoring --strict
	helm template ssf-monitoring k8s/monitoring > /dev/null

app-wait: ## Attend qu'ArgoCD ait synchronisé l'app (Synced, Healthy) et que ses pods soient prêts ; REVISION=<sha> : ce commit-là
	@APP_REVISION=$(REVISION) bash scripts/app-wait.sh

promote: ## Prépare le déploiement d'un commit (SHA=<sha>) : signatures vérifiées, digests écrits dans values-dev.yaml
	@bash scripts/promote.sh $(SHA)

app-proof: ## Preuve 3a : l'app répond via l'ingress, depuis des pods durcis
	$(KUBECTL) -n ssf get pods -o wide
	@echo; echo "== Front, via Traefik :"
	curl -fsS http://127.0.0.1:8081/healthz; echo
	@echo "== API, via le proxy nginx du front (l'Ingress ne route que vers web) :"
	curl -fsS http://127.0.0.1:8081/api/health; echo
	@echo; echo "== Identité des processus (ni root, ni groupe root) :"
	$(KUBECTL) -n ssf exec deploy/web -- id
	$(KUBECTL) -n ssf exec deploy/api -- id
	@echo; echo "== Remplacer la page d'accueil depuis le conteneur (doit ÉCHOUER, lecture seule) :"
	-$(KUBECTL) -n ssf exec deploy/web -- sh -c 'echo defaced > /usr/share/nginx/html/index.html'
	@echo; echo "== Ports publiés par le cluster (127.0.0.1 : rien d'exposé au réseau local) :"
	docker port ssf-dev-control-plane

# Sondes exécutées dans le pod api : le script est envoyé sur l'entrée standard, rien n'est
# copié dans le conteneur (système de fichiers en lecture seule de toute façon).
PROBE = $(KUBECTL) -n ssf exec -i deploy/api -- python -

isolation-proof: ## Preuve 3b : flux réseau et identités — même commande avant et après durcissement
	@echo "############ RÉSEAU ############"
	@echo; echo "== 1. api -> web : mouvement latéral (après durcissement : BLOQUÉ)"
	@$(PROBE) http http://web:8080/healthz < scripts/k8s-probe.py
	@echo; echo "== 2. api -> Internet : exfiltration, téléchargement d'outil (après : BLOQUÉ)"
	@$(PROBE) http https://example.com < scripts/k8s-probe.py
	@echo; echo "== 3. pod d'un autre namespace (default) -> api (après : BLOQUÉ)"
	@$(KUBECTL) -n default run isolation-probe --rm -i --quiet --restart=Never --image=busybox:1.37 --command -- \
	  sh -c 'wget -q -O /dev/null -T 4 http://api.ssf:8000/health && echo "OUVERT   réponse de api.ssf depuis default" || echo "BLOQUÉ   aucune réponse de api.ssf"'
	@echo; echo "== 4. web -> api : flux légitime (après : toujours OUVERT)"
	@$(KUBECTL) -n ssf exec deploy/web -- \
	  sh -c 'wget -q -O /dev/null -T 4 http://api:8000/health && echo "OUVERT   réponse de api depuis web" || echo "BLOQUÉ   aucune réponse de api"'
	@echo; echo "== 5. navigateur -> Traefik -> web -> api : chemin complet (après : toujours OUVERT)"
	@curl -fsS -m 5 -o /dev/null http://127.0.0.1:8081/api/health && echo "OUVERT   127.0.0.1:8081/api/health" || echo "BLOQUÉ   127.0.0.1:8081/api/health"
	@echo; echo "############ IDENTITÉ ############"
	@echo; echo "== 6. jeton Kubernetes monté dans le pod api (après : BLOQUÉ, aucun jeton)"
	@$(PROBE) token < scripts/k8s-probe.py
	@echo; echo "== 7. depuis le pod api, ce jeton s'authentifie auprès de l'API Kubernetes (après : BLOQUÉ)"
	@$(PROBE) whoami < scripts/k8s-probe.py
	@echo; echo "== 8. Traefik peut lire les Secrets hors de ce qu'il sert (après : no)"
	@printf '   Secrets du namespace terraform-state (état Terraform) : '; \
	  $(KUBECTL) auth can-i list secrets -n terraform-state --as=system:serviceaccount:ingress:traefik || true
	@printf '   Secrets de tout le cluster                            : '; \
	  $(KUBECTL) auth can-i list secrets --all-namespaces --as=system:serviceaccount:ingress:traefik || true

supply-chain-proof: ## Preuve jalon 4 : signature, SBOM, digests — même commande avant et après
	@bash scripts/supply-chain-proof.sh

admission-proof: ## Preuve jalon 5a : quelles images le cluster admet (dry-run serveur, rien n'est créé)
	@bash scripts/admission-proof.sh

drift-proof: ## Preuve jalon 5b : cinq modifications manuelles de l'app — le cluster revient-il seul à l'état du dépôt ?
	@bash scripts/drift-proof.sh

drift-check: ## drift-proof + verdict : échoue si une dérive décrite par le dépôt persiste, ou si ArgoCD a trop de droits (CI e2e)
	@DRIFT_STRICT=1 bash scripts/drift-proof.sh

# Verdicts attendus après durcissement, dans l'ordre des tests de isolation-proof.
ISOLATION_EXPECTED := BLOQUÉ BLOQUÉ BLOQUÉ OUVERT OUVERT BLOQUÉ BLOQUÉ no no

isolation-check: ## isolation-proof + verdict : échoue si un seul résultat diffère de l'après attendu (CI e2e)
	@out="$$($(MAKE) --no-print-directory isolation-proof)"; echo "$$out"; \
	  got="$$(echo "$$out" | grep -oE '^(OUVERT|BLOQUÉ)|: (yes|no)$$' | sed 's/^: //' | tr '\n' ' ' | sed 's/ $$//')"; \
	  echo; echo "attendu : $(ISOLATION_EXPECTED)"; echo "obtenu  : $$got"; \
	  if [ "$$got" = "$(ISOLATION_EXPECTED)" ]; then echo "ISOLATION CONFORME"; \
	  else echo "ISOLATION NON CONFORME (sur WSL2, tests 1 à 3 : voir journal jalon 3, incident I8)"; exit 1; fi

infra-lint: chart-lint ## fmt, validate, checkov, trivy config — ce que la CI exécute sur le code Terraform
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

# ---------------------------------------------------------------------------
# DAST (jalon 6a) : l'application vue de l'extérieur, telle qu'un attaquant la voit.
# ---------------------------------------------------------------------------

dast: ## DAST : scan ZAP « baseline » (passif) + 4 expositions ciblées — même commande avant et après
	@bash scripts/dast.sh

dast-check: ## dast + verdict : échoue sur un avertissement ZAP ou une exposition (CI e2e)
	@DAST_STRICT=1 bash scripts/dast.sh

# ---------------------------------------------------------------------------
# Observabilité (jalon 6b) : la posture de sécurité, mesurée en continu.
# ---------------------------------------------------------------------------

posture-proof: ## Preuve 6b : 7 questions de sécurité posées à Prometheus — même commande avant et après
	@bash scripts/posture-proof.sh
