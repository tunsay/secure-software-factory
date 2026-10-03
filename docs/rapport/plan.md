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
| 4 | Chaîne d'approvisionnement | SBOM, signature Cosign, digests | à faire |
| 5 | Policy as code + GitOps | Kyverno, ArgoCD | à faire |
| 6 | Observabilité + DAST + récit | Prometheus/Grafana, ZAP, menaces | à faire |

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

Découpé en deux livrables présentables séparément. Détail, preuves et neuf incidents :
`03-jalon-3.md` ; notes brutes : `journal-jalon-3.md`.

Réalisé : 3a et 3b complets. Écart au plan : les NetworkPolicies ne sont **pas** appliquées sur
le poste (noyau WSL2 sans `NFT_QUEUE`, incident I8) ; elles sont prouvées sur un cluster éphémère
en CI, workflow `e2e` (ADR 0009). Bonus (Sealed Secrets, kube-bench) reportés au jalon 5.

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

## Jalon 4 — Chaîne d'approvisionnement · À FAIRE

Prouver l'intégrité de ce qui est déployé, du build au registre.

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

## Jalon 5 — Policy as code et GitOps · À FAIRE — le plus différenciant

- **Kyverno** dans `security` : interdire le tag `latest`, exiger runAsNonRoot et des limites,
  n'autoriser que le registre GHCR, et **vérifier la signature Cosign à l'admission**.
- Preuve maîtresse : une image non signée poussée à la main est **rejetée par le cluster**, même
  si elle est conforme à PSS. C'est l'argument d'entretien le plus fort du projet.
- **ArgoCD** : dépôt de manifests séparé, synchronisation automatique, démonstration de reprise
  de dérive (modification manuelle du cluster annulée automatiquement).

---

## Jalon 6 — Observabilité, DAST et mise en récit · À FAIRE

- kube-prometheus-stack (Prometheus + Grafana) via Helm, plus un tableau de bord « posture
  sécurité » (vulnérabilités par sévérité, âge des images, dérive de conformité).
- OWASP ZAP baseline en CI contre un environnement éphémère (le D de DAST, complète le SAST/SCA).
- Restreindre `/api/docs` et `/api/metrics` par environnement ; handler d'erreur qui masque
  l'entrée dans les 422 en prod (dettes notées au jalon 1).
- Modèle de menaces STRIDE (`docs/threat-model.md`) relié aux notions EBIOS RM.
- README final, schéma d'architecture, publication de la vitrine sur GitHub Pages.
- Assemblage du PDF du rapport à partir des six chapitres.

---

## Pièges à éviter (transversaux)

- **Fragilité du cluster kind** : jetable, un redémarrage de Docker Desktop l'emporte. Ne rien
  relancer sur l'hôte pendant qu'il tourne ; `make infra-up` reconstruit.
- **Image = outillage offensif** : garder `security/attacks/` à une seule attaque documentée avec
  sa défense. Pas de collection de failles, pas de wording agressif.
- **Dérive vers le dev applicatif** : l'app reste à trois endpoints. Toute extension = nouvel ADR.
- **README pauvre** : lu dix fois plus que le code. Schéma + démo en 3 commandes + menaces
  couvertes, en haut.
