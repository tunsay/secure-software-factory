# Secure Software Factory

> Une application volontairement triviale, entourée d'une chaîne de build, de déploiement
> et de contrôle sécurisée de bout en bout. **Le produit livré n'est pas l'app — c'est la chaîne.**

![CI](https://github.com/tunsay/secure-software-factory/actions/workflows/ci.yml/badge.svg)
![e2e](https://github.com/tunsay/secure-software-factory/actions/workflows/e2e.yml/badge.svg)

## Architecture

```
  git push ──► CI (GitHub Actions, miroir GitLab CI)
               gitleaks · ruff/bandit/semgrep · eslint · pip-audit/npm audit
               Terraform + chart (fmt, validate, Checkov, Trivy) · build · Trivy
                 │
                 │  sur main, si TOUS les contrôles sont verts, par le seul job autorisé :
                 ▼  publication de l'image scannée → SBOM → signature Cosign sans clé → vérification
           ghcr.io : image signée, SBOM attesté, référencée par digest
                 │
                 ▼
  Terraform ──► cluster kind local (1 control-plane, 2 workers)
                 ├─ namespaces Pod Security Standards « restricted »
                 ├─ Traefik (NodePort, 127.0.0.1 uniquement)
                 ├─ NetworkPolicies deny-by-default, comptes de service sans jeton
                 └─ web (React + nginx) ──► api (FastAPI), déployés par digest (chart Helm)

  e2e (CI) ──► même cluster, construit de zéro sur un runner : preuves d'isolation et d'app
```

À venir : Kyverno (signature vérifiée à l'admission) et ArgoCD au jalon 5 ; Prometheus,
Grafana et OWASP ZAP au jalon 6.

## Démo

Prérequis : Windows + WSL2 (Ubuntu) + Docker Desktop, puis `make install-tools`.

```bash
make infra-up            # cluster kind, plateforme et application par Terraform (plan affiché, confirmation)
make app-proof           # l'app répond sur http://localhost:8081 — pods non-root, système de fichiers en lecture seule
make isolation-proof     # cloisonnement réseau et identités (8 tests, même commande avant et après durcissement)
make supply-chain-proof  # signature, SBOM, digest, qui peut signer, build figé
make attack-escape       # une évasion de conteneur, réussie hors durcissement, refusée dans le namespace durci
make scan                # rejoue en local les contrôles de la CI
```

## Ce que la chaîne bloque

| Risque | Contrôle | Où | Depuis |
|---|---|---|---|
| Secret commité | gitleaks (fichiers et historique) | pre-commit + CI | ✅ jalon 1 |
| Code dangereux | ruff, bandit, semgrep, eslint-plugin-security, tsc | CI | ✅ jalon 1 |
| Dépendance vulnérable | pip-audit, npm audit | CI | ✅ jalon 1 |
| Image vulnérable | Trivy, bloquant sur HIGH/CRITICAL | CI | ✅ jalon 1 |
| Infrastructure mal configurée | Checkov, Trivy config | CI | ✅ jalon 2 |
| Conteneur root ou privilégié | Pod Security Standards « restricted » | admission du cluster | ✅ jalon 2 |
| Manifests Kubernetes dangereux | helm lint, Trivy sur le chart rendu | pre-commit + CI | ✅ jalon 3 |
| Mouvement latéral, exfiltration | NetworkPolicies deny-by-default | cluster | ✅ jalon 3 |
| Jeton Kubernetes volé dans un pod | comptes sans jeton, droits de Traefik limités | cluster | ✅ jalon 3 |
| Image publiée malgré un contrôle rouge | publication conditionnée à tous les jobs | CI | ✅ jalon 3 |
| Image d'origine inconnue | signature Cosign sans clé, identité exacte vérifiée | CI | ✅ jalon 4 |
| Contenu non inventorié | SBOM CycloneDX (Syft), signé et attaché à l'image | CI | ✅ jalon 4 |
| Tag déplacé dans le registre | déploiement par digest, refus d'une image sans digest | cluster | ✅ jalon 4 |
| Base d'image ou paquet Python substitué | images de base par digest, `pip --require-hashes` | build | ✅ jalon 4 |
| Signature par un job compromis | permissions CI au moindre privilège | CI | ✅ jalon 4 |
| Dérogation de sécurité oubliée | contrôle des dates d'expiration | CI | ✅ jalon 4 |
| Image non signée déployée | Kyverno, vérification de signature | admission du cluster | ⏳ jalon 5 |
| Dérive de configuration | ArgoCD (GitOps) | cluster | ⏳ jalon 5 |
| Faille visible à l'exécution | OWASP ZAP baseline | CI | ⏳ jalon 6 |

Chaque ligne cochée est prouvée par une commande ou un run de CI, documentés dans le
[rapport](docs/rapport/).

### Limites connues, dites telles quelles

- **NetworkPolicies non appliquées sur le poste** : le noyau WSL2 n'a pas `NFT_QUEUE`, kindnet les
  accepte puis les ignore. Elles sont prouvées à chaque changement sur le cluster éphémère du
  workflow `e2e` ([ADR 0009](docs/adr/0009-preuve-reseau-en-ci-ephemere.md)).
- **Le SBOM du front ne liste pas React** : Vite regroupe les bibliothèques JavaScript dans un seul
  fichier ; les dépendances npm restent contrôlées par `npm audit`, en amont.
- Pas de fournisseur cloud : Terraform pilote un cluster local
  ([ADR 0004](docs/adr/0004-terraform-sans-fournisseur-cloud.md)).

## Rapport et décisions

- [`docs/rapport/`](docs/rapport/) : un chapitre par jalon — ce qui a été construit, les preuves
  avant / après, et chaque incident avec sa leçon.
- [`docs/adr/`](docs/adr/) : les décisions structurantes, une par fichier.

## Arborescence

```
app/api/             FastAPI, 3 endpoints — image multi-stage non-root, dépendances à empreintes
app/web/             React + TS — nginx non privilégié, CSP stricte
infra/terraform/     cluster kind, puis plateforme : namespaces, Traefik, NetworkPolicies, application
k8s/chart/           chart Helm de l'application (image par digest obligatoire)
scripts/             preuves (sondes, supply-chain-proof), contrôle des dérogations, outillage WSL
security/            dérogations datées, démonstration d'attaque encadrée
docs/                rapport par jalon, ADR, plan
.github/workflows/   ci (contrôles, publication signée), e2e (cluster éphémère)
```

## Modèle de menaces

Voir [`docs/threat-model.md`](docs/threat-model.md) (jalon 6).

## Licence

MIT — voir [`LICENSE`](LICENSE).
