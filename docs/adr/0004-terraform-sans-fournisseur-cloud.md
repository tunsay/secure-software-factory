# ADR 0004 — Terraform pilote le cluster local, sans fournisseur cloud

**Statut** : accepté · **Date** : 2026-09-18 · **Remplace** le volet AWS de l'ADR 0002 ; rend l'ADR 0003 sans objet

## Contexte

L'ADR 0002 prévoyait Terraform sur AWS free tier (registre ECR, rôle IAM OIDC, état S3).
L'ouverture d'un compte AWS exige des coordonnées personnelles vérifiées (téléphone, adresse
de facturation rattachée à la carte). Ces informations ne sont pas communiquées pour ce projet.
Les fournisseurs souverains (Scaleway, OVH) imposent une vérification d'identité équivalente.

## Décision

Terraform reste au centre du projet, mais provisionne le **cluster local** et non un cloud :

- **`infra/terraform/cluster`** — crée le cluster kind (provider `tehcyx/kind`). État local :
  c'est le bootstrap, l'équivalent du `bootstrap/` prévu pour AWS.
- **`infra/terraform/platform`** — configure le cluster (providers `kubernetes`, puis `helm`) :
  namespaces, Pod Security Standards, quotas, RBAC, NetworkPolicies, charts. État **distant**
  via le backend `kubernetes` (Secret dans le cluster, verrou natif par lease).
- **Registre d'images : GitHub Container Registry** (ghcr.io) à la place d'ECR. La CI s'y
  authentifie avec le token OIDC de GitHub — aucun secret statique, comme prévu avec IAM OIDC.
  Cosign en mode keyless signe avec cette même identité.
- **Scan du code Terraform** en CI : `terraform fmt`, `validate`, Checkov, `trivy config`.

MinIO a été évalué comme backend S3 local et écarté : dernière release en octobre 2025,
aucun correctif de sécurité depuis.

## Conséquences

- Ce qui est perdu : la preuve de provisioning d'infrastructure cloud (VPC, IAM, stockage).
  Le dépôt ne contient pas de code de provider cloud. C'est assumé et dit tel quel.
- Ce qui est conservé : modules, variables typées, `plan`/`apply`, état distant verrouillé,
  scan IaC en CI, zéro secret statique, signature d'images par OIDC, admission control.
- Ce qui est gagné : tout le durcissement Kubernetes (jalon 3) est écrit en Terraform plutôt
  qu'appliqué à la main — le projet devient intégralement « infrastructure as code ».
- Passage ultérieur à un cloud : ajouter un module avec le provider correspondant ; la couche
  `platform` est indépendante de l'origine du cluster.
- L'état de la couche `platform` vit dans le cluster : sa durée de vie est celle du cluster.
  Un cluster kind est jetable ; le perdre n'est pas un incident, `make infra-up` le reconstruit.
- Limites constatées du provider `tehcyx/kind` : bibliothèque kind embarquée en retard sur
  l'outil installé (formats kubeadm et images de nœuds à aligner sur *sa* version), et plantage
  au `plan` quand le cluster a disparu au lieu de proposer une recréation.
