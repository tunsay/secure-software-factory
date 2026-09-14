# Secure Software Factory

> Une application volontairement triviale, entourée d'une chaîne de build, de déploiement
> et de contrôle sécurisée de bout en bout. **Le produit livré n'est pas l'app — c'est la chaîne.**

![CI](https://github.com/tunsay/secure-software-factory/actions/workflows/ci.yml/badge.svg)

## Architecture

```
                    ┌──────────────────────────────────────────────────────┐
  git push ───────► │  CI  lint → SAST → SCA → build → scan image → sign   │
                    └───────────────┬──────────────────────────────────────┘
                                    │ image signée + SBOM
                                    ▼
   Terraform ──► AWS (ECR, IAM OIDC, S3 state)        kind (local) ◄── ArgoCD
                                                        │
                                            Kyverno ────┤ admission : image signée,
                                                        │ non-root, pas de :latest
                                              ┌─────────┴──────────┐
                                              │  web (React+TS)    │
                                              │  api (FastAPI)     │
                                              └────────────────────┘
```

_(schéma provisoire — `docs/architecture.svg` remplacera ce bloc en semaine 6)_

## Démo en trois commandes

```bash
make up        # build + lance web/api en local (docker compose)
make scan      # rejoue les contrôles de la CI en local
make down
```

- Front : http://localhost:8080
- API : http://localhost:8000/docs — `/health`, `/items`, `/metrics`

## Ce que la chaîne bloque

| Contrôle | Outil | Étage | Statut |
|---|---|---|---|
| Secrets dans l'historique | gitleaks | pre-commit + CI | ✅ S1 |
| SAST Python | bandit, semgrep | CI | ✅ S1 |
| SAST JS/TS | eslint-plugin-security | CI | ✅ S1 |
| Dépendances vulnérables | pip-audit, npm audit | CI | ✅ S1 |
| Vulnérabilités d'image | Trivy (HIGH/CRITICAL bloquant) | CI | ✅ S1 |
| IaC Terraform | Checkov, Trivy config | CI | ⏳ S4 |
| SBOM + signature | Syft, Cosign keyless | CI | ⏳ S4 |
| Admission control | Kyverno | cluster | ⏳ S5 |
| DAST | OWASP ZAP baseline | CI | ⏳ S6 |

## Décisions

Les choix structurants sont documentés en ADR courts dans [`docs/adr/`](docs/adr/).

## Arborescence

```
app/api/        FastAPI — Dockerfile multi-stage, non-root
app/web/        React + TS — nginx unprivileged, CSP stricte
infra/          Terraform (S2)
k8s/            kind, Helm, NetworkPolicies, Kyverno (S3, S5)
security/       exceptions datées, SBOM
docs/adr/       décisions d'architecture
scripts/        outillage (installation WSL, checks)
```

## Modèle de menaces

Voir [`docs/threat-model.md`](docs/threat-model.md) (S6).

## Licence

MIT — voir [`LICENSE`](LICENSE).
