# ADR 0002 — Kubernetes en local (kind), Terraform sur AWS free tier

**Statut** : accepté · **Date** : 2026-09-14

## Contexte

Un cluster EKS coûte environ 70 €/mois même vide. Le projet est développé soirs et
week-ends sur 6 à 8 semaines et doit rester reproductible par n'importe quel lecteur.

## Décision

- Le cluster Kubernetes tourne en local via **kind** (Docker Desktop + WSL2), décrit en YAML,
  monté par `make up`.
- **Terraform** provisionne uniquement ce qui a du sens sur AWS free tier : registre ECR,
  rôle IAM fédéré OIDC pour la CI, bucket S3 chiffré pour l'état distant.
- Aucune clé d'accès AWS statique n'est créée : la CI s'authentifie par OIDC.

## Conséquences

- Coût cible : 0 € en régime permanent. Alerte budget à 1 €.
- La sécurité Kubernetes (RBAC, NetworkPolicies, PSS, admission) se démontre intégralement
  en local.
- Le passage à EKS est documenté comme extension possible, jamais comme prérequis.
