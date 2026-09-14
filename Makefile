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

.PHONY: help setup up down logs build test lint scan scan-image sbom clean install-tools

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

scan: lint scan-image ## Rejoue les contrôles CI en local
	cd app/api && pip-audit -r requirements.txt --strict
	cd app/web && npm audit --audit-level=high
	gitleaks dir . --no-banner --redact
	@if [ -d .git ]; then gitleaks git . --no-banner --redact; else echo "gitleaks git : pas de dépôt, historique non scanné"; fi

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
