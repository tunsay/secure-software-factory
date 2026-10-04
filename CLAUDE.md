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

## Où on en est (4 oct. 2026)

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
- **Jalon 5 — en cours.** 5a (04/10, prouvé en local) : Kyverno 1.19.1 en `Deny` sur `ssf` —
  signature + SBOM par l'identité exacte de la CI, registre `ghcr.io/tunsay/` seul, digest
  obligatoire. Politiques CEL (`ImageValidatingPolicy`, `ValidatingPolicy`) car `ClusterPolicy`
  est dépréciée. `ImageValidatingPolicy` lit bien les bundles cosign v3 sur GHCR (mesuré, J5-I1) :
  double signature de l'ADR 0012 retirée (ADR 0013). Prochain : 5b, ArgoCD.
- **En attente** : trier les PR Dependabot ouvertes (#9 à #17) selon la politique du dépôt.

Les paquets GHCR `ssf-api` et `ssf-web` sont publics (vérifié le 28/09 : tirage anonyme OK).
Ingress : Traefik par NodePort, pas ingress-nginx (retiré en mars 2026) — ADR 0007.
3b (03/10) : NetworkPolicies + comptes sans jeton + Traefik namespacé (ADR 0008). **Le noyau
WSL2 n'a pas NFT_QUEUE : kindnet n'applique pas les NetworkPolicies en local** (incident I8) ;
preuve réseau sur cluster éphémère en CI, workflow `e2e` (ADR 0009).
Journal des incidents du jalon en cours : `docs/rapport/journal-jalon-5.md`.

Le plan directeur complet des 6 jalons est dans `docs/rapport/plan.md`. Jalons 4-6 : SBOM +
signature Cosign keyless + digests (scan IaC déjà là) ; Kyverno + ArgoCD ; observabilité
Prometheus/Grafana + DAST ZAP + modèle de menaces.

## Commandes (toutes depuis WSL Ubuntu, dans /mnt/c/Users/tunas/Documents/Code/secure-software-factory)

```
make help          # liste toutes les cibles
make up / down     # l'app en conteneurs compose (jalon 1) — plus utilisée à partir du jalon 3
make scan          # rejoue toute la CI en local (lint, SAST, SCA, Trivy, gitleaks, semgrep)
make infra-up      # crée le cluster kind puis applique la couche platform (jalon 2)
make infra-down    # détruit platform puis le cluster
make infra-lint    # fmt, validate, checkov, trivy config
make infra-proof   # preuve : pod root refusé par PSS dans le namespace ssf
make attack-escape # démo avant/après : évasion hostPath réussie dans default, bloquée dans ssf
make chart-lint    # helm lint + rendu + trivy du chart k8s/chart (inclus dans infra-lint)
make app-proof     # preuve 3a : app servie par Traefik sur 127.0.0.1:8081, pods non-root, lecture seule
make isolation-proof # preuve 3b : 8 tests réseau + identité, OUVERT/BLOQUÉ (même commande avant/après)
make isolation-check # idem + verdict strict ; échoue en local sur les tests réseau (WSL2, incident I8)
make supply-chain-proof # preuve jalon 4 : signature, SBOM, digest, qui peut signer, build figé
make admission-proof # preuve 5a : 6 images soumises au cluster en dry-run serveur, ADMISE/REFUSÉE
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
  Déployer une image = reporter tag ET digests du résumé du job `images` dans `dev.tfvars`.
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
