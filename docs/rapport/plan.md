# Plan du projet — Secure Software Factory

Plan directeur des six jalons. Tenu à jour au fil du projet ; reflète les décisions prises
(notamment l'ADR 0004 qui a écarté le cloud au jalon 2).

## Principe

Une application volontairement triviale (API FastAPI à trois endpoints + une page React),
entourée d'une chaîne de build, de déploiement et de contrôle sécurisée de bout en bout.
**Le produit livré n'est pas l'app, c'est la chaîne.** Calibré sur 10 offres DevSecOps CDI
d'Île-de-France (voir `00-contexte.md`).

Contraintes : développement soirs et week-ends, ~6 à 8 semaines, cluster local (kind), aucun
fournisseur cloud (ADR 0004), coût zéro.

## Vue d'ensemble

| Jalon | Objet | Cœur | État |
|---|---|---|---|
| 1 | Socle applicatif + chaîne de contrôle | pipeline SAST/SCA/scan | **terminé** |
| 2 | Terraform pilote le cluster | PSS restricted, GHCR OIDC, job IaC | **terminé** |
| 3 | Déploiement + cloisonnement | Helm, Traefik, NetworkPolicies, RBAC, preuve e2e | **terminé** |
| 4 | Chaîne d'approvisionnement | SBOM, signature Cosign, digests, empreintes, moindre privilège CI | **terminé** |
| 5 | Policy as code + GitOps | Kyverno (signature à l'admission), ArgoCD sans droits de cluster | **terminé** |
| 6 | Observabilité + DAST + récit | ZAP bloquant, Prometheus/Grafana, trivy-operator, menaces, vitrine | **terminé** |

---

## Jalon 1 — Socle applicatif et chaîne de contrôle · TERMINÉ

Application minimale, images durcies, chaîne de scan locale (`make scan`) et CI.

- API FastAPI (`/health`, `/items`, `/metrics`), front React+TS d'une page derrière nginx.
- Images multi-stage, non-root, sans gestionnaire de paquets, correctifs OS au build.
- Contrôles bloquants : gitleaks, ruff, bandit, semgrep, eslint-security, pip-audit, npm audit,
  Trivy, smoke test. Hooks pre-commit.
- CI GitHub (6 jobs) + miroir GitLab, actions épinglées par SHA, Dependabot avec cooldown.

Preuve : conteneur verrouillé (non-root, read-only, cap_drop ALL, pas de socket Docker).
Détail et incidents : `01-jalon-1.md`.

---

## Jalon 2 — Terraform pilote le cluster · TERMINÉ

Terraform crée et configure un cluster kind local. Pas de cloud (ADR 0004).

- `cluster/` : kind par Terraform, image épinglée par digest, état local.
- `platform/` : namespaces durcis, état distant dans le cluster, verrou par lease.
- Module `namespace` : PSS restricted en enforce, quota, limites par défaut ; refuse `privileged`.
- Registre GHCR : push sur `main` avec le token OIDC du job, zéro secret statique.
- Job CI `iac` : fmt, validate, Checkov → Security, trivy config.

Preuve : pod root refusé à l'admission ; démonstration avant/après (`make attack-escape`) —
évasion hostPath réussie dans `default`, bloquée dans `ssf`. Détail et incidents : `02-jalon-2.md`.

---

## Jalon 3 — Déploiement dans le cluster et cloisonnement · TERMINÉ

Découpé en deux livrables présentables séparément. Détail, preuves et dix incidents :
`03-jalon-3.md` ; notes brutes : `journal-jalon-3.md`.

Réalisé : 3a et 3b complets. Écart au plan : les NetworkPolicies ne sont **pas** appliquées sur
le poste (noyau WSL2 sans `NFT_QUEUE`, incident I8) ; elles sont prouvées sur un cluster éphémère
en CI, workflow `e2e` (ADR 0009). Bonus (Sealed Secrets, kube-bench) reportés au jalon 5, puis
abandonnés (voir jalon 5).

Prérequis : paquets GHCR `ssf-api` et `ssf-web` publics — vérifié, c'était déjà le cas.

### 3a — l'application tourne dans le cluster

- Chart Helm maison (deployment, service, ingress sur 8081), installé par le provider `helm`.
  Pas de HPA : l'API stocke en mémoire (une seule réplique possible), pas de metrics-server.
- Ingress controller Traefik exposé par NodePort, en PSS restricted (ADR 0007) —
  ingress-nginx est retiré depuis mars 2026.
- Déploiement de l'app depuis GHCR dans le namespace `ssf`, conforme à PSS restricted
  (securityContext complet : runAsNonRoot, drop ALL, seccomp, allowPrivilegeEscalation=false).
- `http://localhost:8081` répond depuis un pod durci.
- Attention : le provider `helm` 3.x a changé de syntaxe — vérifier avant d'écrire.

### 3b — le cluster est cloisonné

- NetworkPolicies deny-by-default sur `ssf`, puis ouverture flux par flux (web→api uniquement).
- Vérifier que kindnet applique bien les NetworkPolicies (selon version).
- RBAC au strict minimum, ServiceAccount dédié, token non monté par défaut.
- Preuve clé : l'API ne peut plus joindre le front — l'« après » du test réseau du jalon 1
  (au jalon 1, `python -c urllib...http://web:8080` réussissait ; ici il doit échouer).

### Bonus (ou reporté au jalon 5)

- Sealed Secrets dans `security` — rien de déchiffrable dans le dépôt.
- Score kube-bench / kubescape avant et après durcissement, capturé.

---

## Jalon 4 — Chaîne d'approvisionnement · TERMINÉ

Prouver l'intégrité de ce qui est déployé, du build au registre. Détail, preuves et sept
incidents : `04-jalon-4.md` ; notes brutes : `journal-jalon-4.md`.

Réalisé : tout le périmètre ci-dessous, plus le moindre privilège des jobs CI (ADR 0011), la
publication de l'image exacte qui a été scannée, et l'état Terraform du cluster sorti du dépôt.
Écart au plan : le SBOM n'est pas exhaustif — le code JavaScript regroupé par Vite n'y apparaît
pas comme bibliothèques (angle mort documenté).

- SBOM CycloneDX généré par Syft à chaque build, publié comme artefact.
- Signature des images par Cosign en mode **keyless** (identité OIDC GitHub — cohérent avec le
  zéro-secret du jalon 2).
- Images de base épinglées par **digest** (pas seulement par tag) ; Dependabot fait tourner le
  digest.
- `--require-hashes` sur les dépendances Python (pip-compile --generate-hashes).
- Le scan IaC (Checkov, trivy config) est déjà en place depuis le jalon 2.

Preuve : une image modifiée après signature est détectable ; le SBOM liste exhaustivement les
composants.

---

## Jalon 5 — Policy as code et GitOps · TERMINÉ

Le cluster refuse lui-même ce qui ne vient pas de la chaîne, et revient seul à l'état décrit
dans le dépôt. Détail, preuves et trois incidents : `05-jalon-5.md` ; notes brutes :
`journal-jalon-5.md`.

- **5a — Kyverno 1.19.1** dans `security`, politiques CEL (`ImageValidatingPolicy`,
  `ValidatingPolicy`) en `Deny` sur `ssf` : signature **et** SBOM par l'identité exacte du
  workflow `ci` sur `main`, registre `ghcr.io/tunsay/` seul, digest obligatoire. Preuve
  (`make admission-proof`) : une image jamais signée, conforme à PSS, est refusée par le
  cluster — la preuve maîtresse du plan. ADR 0012 et 0013.
- **5b — Argo CD v3.5.3** : déploie l'application depuis ce dépôt (`k8s/chart` +
  `values-dev.yaml`), synchronisation automatique, modifications manuelles annulées (`selfHeal`).
  **Aucun droit de cluster** (par défaut : administrateur de tout le cluster), aucun compte.
  Preuve (`make drift-proof`, et `make drift-check` en CI à chaque changement). ADR 0014.

Écarts au plan, décidés par Tunsay :

- **Pas de dépôt de manifests séparé** : ArgoCD lit ce dépôt. Le workflow e2e déploie
  exactement le commit testé, et la CI n'a besoin d'aucun jeton d'écriture (ADR 0014).
- **runAsNonRoot et limites non doublés dans Kyverno** : déjà imposés par PSS restricted et le
  LimitRange depuis le jalon 2. Le LimitRange injecte les limites avant que Kyverno voie le pod :
  une règle Kyverno « limites » ne pourrait jamais échouer dans `ssf`.
- **Sealed Secrets et kube-bench abandonnés** : l'application n'a aucun secret à protéger
  (zéro secret statique, OIDC partout) ; kube-bench s'exécute en pod privilégié (hostPID,
  montages du nœud), à l'opposé de la posture du cluster.

---

## Jalon 6 — Observabilité, DAST et mise en récit · TERMINÉ

Regarder l'application comme un attaquant, voir ce que la chaîne refuse et répare, expliquer
pourquoi chaque contrôle existe. Détail, preuves et deux incidents : `06-jalon-6.md` ; notes
brutes : `journal-jalon-6.md`.

- **6a — DAST** : OWASP ZAP 2.17.0 et quatre expositions ciblées (`make dast`), bloquant en CI
  e2e. Avant : 5 avertissements, interfaces internes publiques, entrée renvoyée dans les 422.
  Après : 0 et 0. Le DAST a trouvé un défaut invisible aux outils statiques : les en-têtes de
  sécurité perdus sur les fichiers JS et CSS (héritage `add_header` de nginx).
- **6b — observabilité** : Prometheus + Grafana (sans node-exporter ni Alertmanager, Grafana
  namespacé et sans compte), trivy-operator aux droits écrits par nous, 6 alertes de sécurité,
  tableau de bord « posture ». `make posture-proof` : 7 questions, avant sans réponse, après
  7 sur 7. ADR 0015.
- **6c — modèle de menaces** : `docs/threat-model.md`, STRIDE cadré par les cinq ateliers
  d'EBIOS RM, chaque contrôle relié à une preuve exécutable, risques résiduels assumés.
- **6d — vitrine** : README final, GitHub Pages (dossier `docs/`), `make report-pdf`.

Écarts au plan : pas d'« âge des images » (aucune métrique standard) ; `/api/docs`, `/api/metrics`
et l'écho des 422 fermés **partout**, pas seulement en prod (l'environnement exposé est `dev`).

---

## Pièges à éviter (transversaux)

- **Fragilité du cluster kind** : jetable, un redémarrage de Docker Desktop l'emporte. Ne rien
  relancer sur l'hôte pendant qu'il tourne ; `make infra-up` reconstruit.
- **Image = outillage offensif** : garder `security/attacks/` à une seule attaque documentée avec
  sa défense. Pas de collection de failles, pas de wording agressif.
- **Dérive vers le dev applicatif** : l'app reste à trois endpoints. Toute extension = nouvel ADR.
- **README pauvre** : lu dix fois plus que le code. Schéma + démo en 3 commandes + menaces
  couvertes, en haut.
