# CLAUDE.md — contexte du projet pour l'assistant

## Ce qu'est ce projet

**Secure Software Factory** — un projet portfolio DevSecOps de Tunsay, destiné à démontrer, face
à des recruteurs en Île-de-France, la maîtrise d'une chaîne de build/déploiement/contrôle
sécurisée de bout en bout.

Principe directeur (ADR 0001) : **l'application est volontairement triviale**. Le produit
démontré n'est pas l'app, c'est la chaîne autour. Ne jamais étoffer l'app au-delà de ses trois
endpoints sans un nouvel ADR — ça diluerait le positionnement sécurité-first.

Stack décidée après analyse de 10 offres DevSecOps CDI (voir `docs/rapport/00-contexte.md`) :
React+TypeScript (front minimal), Python/FastAPI (back), Terraform, Kubernetes (kind local),
GitHub Actions + GitLab CI en miroir, GHCR.

## Où on en est (5 oct. 2026)

- **Jalon 1 — terminé.** App minimale, images durcies, chaîne de scan locale + CI. Voir
  `docs/rapport/01-jalon-1.md`.
- **Jalon 2 — terminé.** Terraform pilote un cluster kind local (pas de cloud — voir ADR 0004,
  le compte AWS a été écarté car Tunsay ne veut pas communiquer ses coordonnées). Namespaces
  durcis PSS restricted, backend d'état distant, registre GHCR par OIDC, job IaC en CI,
  démonstration d'attaque avant/après. Voir `docs/rapport/02-jalon-2.md`.
- **Jalon 3 — terminé (03/10).** 3a : app déployée par Terraform + Helm derrière Traefik
  (NodePort, 127.0.0.1). 3b : NetworkPolicies, comptes sans jeton, Traefik namespacé, preuve
  sur cluster éphémère en CI (workflow `e2e`). Dix incidents. Voir `docs/rapport/03-jalon-3.md`.
  Sealed Secrets + kube-bench reportés au jalon 5.
- **Jalon 4 — terminé (03/10).** Images publiées telles que scannées, SBOM attesté, signature
  Cosign sans clé par le seul job `images` (identité exacte `ci.yml@refs/heads/main`), déploiement
  par `tag@digest`, bases par digest, `requirements.txt` à empreintes, contrôle des dérogations.
  Sept incidents. Voir `docs/rapport/04-jalon-4.md`, ADR 0010 et 0011.
- **Jalon 5 — terminé (04/10).** 5a : Kyverno 1.19.1 en `Deny` sur `ssf` — signature + SBOM
  par l'identité exacte de la CI, registre `ghcr.io/tunsay/` seul, digest obligatoire ; politiques
  CEL (`ClusterPolicy` est dépréciée) ; signature cosign v3 seule (ADR 0012, 0013). 5b : Argo CD
  v3.5.3 déploie l'app depuis ce dépôt (`k8s/chart` + `values-dev.yaml`), `selfHeal`, **sans droits
  de cluster** ni compte (ADR 0014) ; Terraform ne déploie plus l'app. Trois incidents. Voir
  `docs/rapport/05-jalon-5.md`. Écarts au plan : pas de dépôt séparé, runAsNonRoot/limites laissés
  à PSS, Sealed Secrets et kube-bench abandonnés.
- **Jalon 6 — terminé (05/10).** Voir `docs/rapport/06-jalon-6.md` (journal :
  `journal-jalon-6.md`, J6-I1, J6-I2) et ADR 0015.
  - 6a : `make dast` (ZAP 2.17.0 + 4 expositions ciblées), avant 5 avertissements et 4 expositions,
    après 0 et 0 ; `make dast-check` bloquant en e2e. `make promote SHA=` vérifie signature + SBOM
    puis écrit `values-dev.yaml`.
  - 6b : Prometheus + Grafana (kube-prometheus-stack 91.7.1, sans node-exporter ni Alertmanager,
    Grafana namespacé et sans compte), trivy-operator aux **droits écrits par nous** (`trivy.tf`),
    6 alertes `famille=securite`, tableau de bord « posture » ; `make posture-proof` : 7/7.
  - 6c : `docs/threat-model.md`, STRIDE cadré par les 5 ateliers d'EBIOS RM, chaque contrôle relié
    à une preuve exécutable. 6d : README final, `docs/index.md` (GitHub Pages, dossier `docs/`),
    `make report-pdf` (pandoc 3.11 + Typst, image par digest).
- **Le plan des 6 jalons est terminé.** Suites possibles, dans l'ordre : trier les PR Dependabot ;
  points ouverts du chapitre 6 (images d'outils CI par digest, signature des images de plateforme,
  KSV-0125/0020/0021/0039) ; captures d'écran des jalons 3 à 6 (`docs/rapport/img/`).

Les paquets GHCR `ssf-api` et `ssf-web` sont publics (vérifié le 28/09 : tirage anonyme OK).
Ingress : Traefik par NodePort, pas ingress-nginx (retiré en mars 2026) — ADR 0007.
3b (03/10) : NetworkPolicies + comptes sans jeton + Traefik namespacé (ADR 0008). **Le noyau
WSL2 n'a pas NFT_QUEUE : kindnet n'applique pas les NetworkPolicies en local** (incident I8) ;
preuve réseau sur cluster éphémère en CI, workflow `e2e` (ADR 0009).
Dernier journal d'incidents : `docs/rapport/journal-jalon-5.md` (le jalon 6 aura le sien).

Le plan directeur complet des 6 jalons est dans `docs/rapport/plan.md`. Jalons 4-6 : SBOM +
signature Cosign keyless + digests (scan IaC déjà là) ; Kyverno + ArgoCD ; observabilité
Prometheus/Grafana + DAST ZAP + modèle de menaces.

## Commandes (toutes depuis WSL Ubuntu, dans /mnt/c/Users/tunas/Documents/Code/secure-software-factory)

```
make help          # liste toutes les cibles
make up / down     # l'app en conteneurs compose (jalon 1) — plus utilisée à partir du jalon 3
make scan          # rejoue toute la CI en local (lint, SAST, SCA, Trivy, gitleaks, semgrep)
make infra-up      # cluster kind + couche platform (Terraform), puis attend qu'ArgoCD ait déployé l'app
make infra-down    # détruit platform puis le cluster
make infra-lint    # fmt, validate, checkov, trivy config
make infra-proof   # preuve : pod root refusé par PSS dans le namespace ssf
make attack-escape # démo avant/après : évasion hostPath réussie dans default, bloquée dans ssf
make chart-lint    # helm lint + rendu des 3 charts (app avec values-dev.yaml, policies, argocd) + trivy
make app-proof     # preuve 3a : app servie par Traefik sur 127.0.0.1:8081, pods non-root, lecture seule
make isolation-proof # preuve 3b : 8 tests réseau + identité, OUVERT/BLOQUÉ (même commande avant/après)
make isolation-check # idem + verdict strict ; échoue en local sur les tests réseau (WSL2, incident I8)
make supply-chain-proof # preuve jalon 4 : signature, SBOM, digest, qui peut signer, build figé
make admission-proof # preuve 5a : 6 images soumises au cluster en dry-run serveur, ADMISE/REFUSÉE
make drift-proof   # preuve 5b : 5 dérives manuelles, ANNULÉE/PERSISTANTE, + droits d'ArgoCD
make drift-check   # idem + verdict strict (CI e2e)
make app-wait      # attend Synced/Healthy d'ArgoCD et les pods prêts (appelé par infra-up) ; REVISION=<sha>
make promote SHA=<sha> # vérifie signature + SBOM des images d'un commit, écrit values-dev.yaml (sans commiter)
make dast          # preuve 6a : ZAP baseline + 4 expositions ciblées (dast-check : strict, CI e2e)
make posture-proof # preuve 6b : 7 questions de sécurité posées à Prometheus
make report-pdf    # rapport complet (chapitres 0 à 6 + modèle de menaces) : docs/rapport/rapport.pdf
```

Reprise de session : `docker ps --format '{{.Names}}' | grep ssf-dev || make infra-up`.

## Environnement et pièges connus (tous rencontrés et documentés)

- **OS** : Windows 11 + WSL2 Ubuntu 22.04 + Docker Desktop (intégration WSL activée). Le projet
  vit sur `/mnt/c/...` — plus lent que `~/` mais fonctionnel. Toujours travailler dans WSL, pas
  PowerShell.
- **cgroup v2 requis** : `.wslconfig` a été configuré (`cgroup_no_v1=all`). Kubernetes ≥1.31
  refuse cgroup v1.
- **Provider `tehcyx/kind` 0.11.0** embarque kind 0.31 → génère du kubeadm `v1beta3`
  (`kubeletExtraArgs` en **map**, pas en liste), et n'accepte que les images de nœuds de kind
  0.31 : image épinglée `kindest/node:v1.35.0@sha256:452d70...`. Ne pas monter à v1.37.
- **Ports ingress 8081/8444** (pas 80/443, refusés par le relais réseau de Docker Desktop sous
  Windows ; pas 8080/8000, pris par compose).
- **Dépôt sur `/mnt/c`, partagé entre git WSL et git Windows** : collisions sur
  `.git/index.lock` pendant les hooks (incident I10 du jalon 3). Réglé par
  `core.trustctime=false` + `core.checkStat=minimal` dans `.git/config`. Côté Windows, l'assistant
  n'utilise git qu'en `git --no-optional-locks` (lecture seule).
- **NetworkPolicies non appliquées en local** : le noyau WSL2 n'a pas `NFT_QUEUE` (incident I8) ;
  la preuve réseau se fait en CI (workflow `e2e`). `make isolation-check` échoue en local, c'est
  attendu.
- **État Terraform de la couche cluster hors du dépôt** : `~/.local/state/ssf/cluster.tfstate`
  (il contient la clé privée administrateur du cluster ; incident J4-I6). Ne jamais le remettre
  dans `infra/terraform/cluster/`.
- **Docker dans WSL ne télécharge plus d'image publique** (`error getting credentials`) : assistant
  d'identifiants de Docker Desktop. Contournement ponctuel :
  `DOCKER_CONFIG=$(mktemp -d) docker pull <image>`.
- **Python 3.10 dans WSL, 3.14 dans l'image et la CI** : le venv local s'installe depuis
  `requirements.in` (sans empreintes). `requirements.txt` se régénère dans l'image de production
  (commande en tête de `app/api/requirements.in`), jamais avec le Python du poste.
- **Un cluster kind est jetable** : un redémarrage de Docker Desktop l'emporte, avec l'état
  platform qu'il contient. `make infra-up` reconstruit tout. Le provider plante au `plan` si le
  cluster a disparu → `terraform state rm kind_cluster.this` puis `apply`.
- **Kyverno en `Deny` avec `failurePolicy: Fail`** : si Kyverno est arrêté ou ne joint pas
  GHCR/Rekor, aucun pod ne se crée dans `ssf` (voulu : « pas pu contrôler » vaut « refusé »).
  Déployer une image = reporter tag ET digests du résumé du job `images` dans
  `k8s/chart/values-dev.yaml`, commiter, pousser : ArgoCD applique (jalon 5b).
- **ArgoCD lit GitHub, pas le poste** : il déploie `main` tel que poussé (relecture toutes les
  2 à 3 min). Un changement de `k8s/` non poussé n'est pas déployé. Interface (lecture seule,
  sans compte) : `kubectl -n argocd port-forward svc/argocd-server 8090:443`, puis
  https://127.0.0.1:8090.
- **Constater une recréation de pods** : `kubectl wait --for=condition=Ready pod -l ...`, jamais
  `kubectl rollout status` (il répond « terminé » si le Deployment n'a pas changé ; J5-I2).

## Conventions du dépôt (à respecter absolument)

- **Actions GitHub épinglées par SHA** de commit (jamais un tag flottant), tag en commentaire.
- **Images taguées par SHA**, jamais `latest` ; déployées par `tag@digest` ; images de base des
  Dockerfiles épinglées par digest.
- **Dépendances Python** : on modifie `app/api/requirements.in`, on régénère `requirements.txt`
  (empreintes) ; installation de l'application toujours en `--require-hashes`.
- **Permissions CI au moindre privilège** : `contents: read` au niveau du workflow, droits
  d'écriture job par job ; `id-token` et `packages` réservés au job `images` (ADR 0011).
- **Machines de CI figées** (`runs-on: ubuntu-24.04`), jamais `ubuntu-latest` : une montée de
  version du système de la CI est un commit choisi et vérifié.
- **Aucun secret statique** : la CI pousse sur GHCR avec le `GITHUB_TOKEN` du job (OIDC).
- **Zéro secret dans le dépôt** : gitleaks en pre-commit + CI. `.tfstate`, `.tfvars` sensibles et
  `*.sarif` sont dans `.gitignore`.
- **Commits conventionnels** : `feat:`, `fix:`, `sec:`, `infra:`, `docs:`, `ci:`, `chore:`.
  Vérifié par un hook commit-msg.
- **Dependabot** avec cooldown 7 jours (pip, npm, docker, github-actions, terraform). PRs triées
  à la main selon une politique : LTS uniquement pour les images, pas de saut de version majeure
  qui casse une dépendance pair. Ne jamais merger en aveugle.
- **Un ADR par décision structurante** dans `docs/adr/`, jamais modifié après coup (une décision
  annulée est remplacée par un nouvel ADR qui la référence).
- **Un chapitre de rapport par jalon** dans `docs/rapport/`, rédigé en fin de jalon, avec les
  incidents rencontrés et leurs leçons — c'est le matériau d'entretien de Tunsay. Captures dans
  `docs/rapport/img/` (Tunsay les prend lui-même).
- **`security/attacks/`** contient un manifeste d'attaque réel (évasion hostPath) à but
  pédagogique, encadré par son README. Garder ce cadrage : une seule attaque, documentée, avec
  sa défense à côté — ne pas transformer le dépôt en outillage offensif.

## Méthode de travail attendue

- **Vérifier avant d'écrire** : toujours confirmer la version courante d'un outil/action/image
  (registre, API GitHub) avant de l'épingler. Ne pas deviner.
- **Valider avant de livrer** : rejouer `make scan` / `make infra-lint` avant chaque commit.
  Le sandbox de l'assistant peut être indisponible (bug Windows virtiofs de sept. 2026) — dans
  ce cas, donner les commandes à Tunsay qui les exécute et colle la sortie.
- **Shift-left** : corriger le plus tôt possible (pre-commit > make scan > CI). Un historique
  « cassé → réparé » vaut mieux évité, mais quand un contrôle attrape une vraie faille, c'est un
  succès à raconter, pas à cacher.
- **Réponses concises et directes** (préférence de Tunsay), en français.
- Tunsay apprend en même temps qu'il construit : expliquer le *pourquoi* de chaque choix, pas
  seulement le *comment*.
