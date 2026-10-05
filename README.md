# Secure Software Factory

> Une application volontairement triviale, entourée d'une chaîne de build, de déploiement
> et de contrôle sécurisée de bout en bout. **Le produit livré n'est pas l'app — c'est la chaîne.**

![CI](https://github.com/tunsay/secure-software-factory/actions/workflows/ci.yml/badge.svg)
![e2e](https://github.com/tunsay/secure-software-factory/actions/workflows/e2e.yml/badge.svg)

**La question de fond** : ce qui tourne dans le cluster est-il exactement ce qui a été contrôlé —
et le saurait-on sinon ? Chaque contrôle ci-dessous est **prouvé par une commande** ou un run de
CI qui échoue s'il disparaît. Rapport complet, décisions et modèle de menaces :
[`docs/`](docs/) (aussi publié sur GitHub Pages).

## Architecture

```
  git push ──► CI (GitHub Actions, miroir GitLab CI)
               gitleaks · ruff/bandit/semgrep · eslint · pip-audit/npm audit
               Terraform + charts (fmt, validate, Checkov, Trivy) · build · Trivy
                 │
                 │  sur main, si TOUS les contrôles sont verts, par le seul job autorisé :
                 ▼  publication de l'image scannée → SBOM → signature Cosign sans clé → vérification
           ghcr.io : image signée, SBOM attesté, référencée par digest
                 │
                 │  déployer = un commit sur values-dev.yaml (make promote vérifie la signature avant)
                 ▼
  Terraform ──► cluster kind local (1 control-plane, 2 workers) : la plateforme
                 ├─ namespaces Pod Security Standards « restricted », quotas
                 ├─ Traefik (NodePort, 127.0.0.1 uniquement)
                 ├─ NetworkPolicies deny-by-default, comptes de service sans jeton
                 ├─ Kyverno : n'admet que les images signées par la CI, de ghcr.io/tunsay, par digest
                 ├─ ArgoCD, sans droits de cluster : n'écrit que dans ssf, annule toute dérive
                 ├─ Prometheus + Grafana : posture de sécurité, 6 alertes
                 └─ trivy-operator, droits restreints : rescanne en continu ce qui tourne
                      │
                      ▼
                    web (React + nginx) ──► api (FastAPI), par digest, admis par Kyverno

  e2e (CI) ──► même cluster, construit de zéro sur un runner :
               isolation réseau · application · DAST (ZAP) · dérive et droits d'ArgoCD
```

## Démo

Prérequis : Windows + WSL2 (Ubuntu) + Docker Desktop, puis `make install-tools`.

```bash
make infra-up            # cluster kind et plateforme par Terraform (plan affiché, confirmation), puis ArgoCD déploie l'app
make app-proof           # l'app répond sur http://localhost:8081 — pods non-root, système de fichiers en lecture seule
make isolation-proof     # cloisonnement réseau et identités (8 tests, même commande avant et après durcissement)
make supply-chain-proof  # signature, SBOM, digest, qui peut signer, build figé
make admission-proof     # 6 images soumises au cluster : seules celles signées par la CI, par digest, sont admises
make drift-proof         # 5 modifications manuelles de l'app : celles que le dépôt décrit sont annulées par ArgoCD
make dast                # l'app vue de l'extérieur : ZAP + 4 expositions ciblées
make posture-proof       # 7 questions de sécurité posées à Prometheus : refus, dérive, failles, alertes
make attack-escape       # une évasion de conteneur, réussie hors durcissement, refusée dans le namespace durci
make scan                # rejoue en local les contrôles de la CI
make report-pdf          # le rapport complet en PDF
```

## Ce que la chaîne bloque et détecte

| Risque | Contrôle | Où | Depuis |
|---|---|---|---|
| Secret commité | gitleaks (fichiers et historique) | pre-commit + CI | ✅ jalon 1 |
| Code dangereux | ruff, bandit, semgrep, eslint-plugin-security, tsc | CI | ✅ jalon 1 |
| Dépendance vulnérable | pip-audit, npm audit | CI | ✅ jalon 1 |
| Image vulnérable | Trivy, bloquant sur HIGH/CRITICAL corrigeables | CI | ✅ jalon 1 |
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
| Image non signée déployée, même conforme à PSS | Kyverno : signature et SBOM par l'identité exacte de la CI | admission du cluster | ✅ jalon 5 |
| Image d'un autre registre, ou désignée par un tag | Kyverno : `ghcr.io/tunsay/` seul, digest obligatoire | admission du cluster | ✅ jalon 5 |
| Modification manuelle du cluster (dérive) | ArgoCD, synchronisation automatique avec `selfHeal` | cluster | ✅ jalon 5 |
| Outil de déploiement compromis | ArgoCD sans droits de cluster : écrit dans `ssf` seulement, aucun compte | cluster | ✅ jalon 5 |
| Faille visible seulement à l'exécution | OWASP ZAP, bloquant ; en-têtes sur toutes les réponses | CI (e2e) | ✅ jalon 6 |
| Interface interne exposée, entrée renvoyée | métriques, OpenAPI, Swagger refusés au public ; 422 sans écho | CI (e2e) | ✅ jalon 6 |
| Faille publiée **après** le déploiement | trivy-operator rescanne en continu ; alerte sur faille critique | cluster | ✅ jalon 6 |
| Refus, dérive ou panne passés inaperçus | Prometheus, Grafana « posture sécurité », 6 alertes de sécurité | cluster | ✅ jalon 6 |
| Outil d'exploitation trop privilégié | Grafana et trivy-operator aux droits restreints (défaut : tous les Secrets) | cluster | ✅ jalon 6 |

### Limites connues, dites telles quelles

- **Le compte GitHub est le point de défaillance unique** : qui le contrôle signe et déploie
  « légitimement ». En équipe : protection de branche, revue obligatoire, environnement protégé
  ([modèle de menaces](docs/threat-model.md), atelier 5).
- **NetworkPolicies non appliquées sur le poste** : le noyau WSL2 n'a pas `NFT_QUEUE`, kindnet les
  accepte puis les ignore. Elles sont prouvées à chaque changement sur le cluster éphémère du
  workflow `e2e` ([ADR 0009](docs/adr/0009-preuve-reseau-en-ci-ephemere.md)).
- **ArgoCD n'annule que ce que le dépôt décrit** : un champ ajouté à la main, ou un objet étranger
  créé dans le namespace, restent (mesuré) ; ce sont les droits Kubernetes et Kyverno qui limitent
  ce cas ([ADR 0014](docs/adr/0014-gitops-argocd-sans-droits-cluster.md)).
- **L'image de l'API porte 5 failles hautes sans correctif publié** (ncurses, perl-base) : la CI
  les tolère par politique, trivy-operator les affiche en continu.
- **Sur le poste, la réparation d'une dérive a pris ~90 s** au lieu de 9 à 27 s en CI : Kyverno
  vérifie aussi les Deployments, sa vérification de signature est sur le chemin du déploiement
  ([chapitre 5](docs/rapport/05-jalon-5.md), incident 3).
- **Le SBOM du front ne liste pas React** : Vite regroupe les bibliothèques JavaScript dans un seul
  fichier ; les dépendances npm restent contrôlées par `npm audit`, en amont.
- Pas d'Alertmanager : les alertes s'affichent, personne n'est prévenu. Pas de fournisseur cloud :
  Terraform pilote un cluster local ([ADR 0004](docs/adr/0004-terraform-sans-fournisseur-cloud.md)).

## Rapport, décisions, menaces

- [`docs/rapport/`](docs/rapport/) : un chapitre par jalon — ce qui a été construit, les preuves
  avant / après, et chaque incident avec sa leçon ; la [conclusion](docs/rapport/07-conclusion.md)
  montre comment les jalons s'emboîtent et résume de quoi on est protégé (`make report-pdf` pour
  la version PDF).
- [`docs/threat-model.md`](docs/threat-model.md) : STRIDE cadré par les ateliers d'EBIOS RM,
  chaque menace reliée à son contrôle et à sa preuve exécutable, risques résiduels assumés.
- [`docs/adr/`](docs/adr/) : les décisions structurantes, une par fichier.

## Arborescence

```
app/api/             FastAPI, 3 endpoints — image multi-stage non-root, dépendances à empreintes
app/web/             React + TS — nginx non privilégié, CSP stricte sur toutes les réponses
infra/terraform/     cluster kind, puis plateforme : namespaces, Traefik, NetworkPolicies, Kyverno,
                     ArgoCD, Prometheus/Grafana, trivy-operator — et les droits de chacun
k8s/chart/           chart Helm de l'application (image par digest obligatoire), values-dev.yaml = version déployée
k8s/policies/        politiques d'admission Kyverno (signature, registre, digest)
k8s/argocd/          projet et Application ArgoCD (ce dépôt, namespace ssf, rien d'autre)
k8s/monitoring/      sonde de l'API, alertes de sécurité, tableau de bord « posture »
scripts/             preuves (isolation, supply-chain, admission, dérive, DAST, posture), promotion, outillage
security/            dérogations datées, règles ZAP, démonstration d'attaque encadrée
docs/                rapport par jalon, ADR, modèle de menaces, plan
.github/workflows/   ci (contrôles, publication signée), e2e (cluster éphémère : isolation, app, DAST, dérive)
```

## Licence

MIT — voir [`LICENSE`](LICENSE).
