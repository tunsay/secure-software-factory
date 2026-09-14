# ADR 0001 — L'application est volontairement triviale

**Statut** : accepté · **Date** : 2026-09-14

## Contexte

Le projet est une vitrine DevSecOps. Sur 10 offres DevSecOps CDI analysées en Île-de-France
(sept. 2026), deux seulement nomment un framework front-end, et aucun ne domine. Ce qui est
évalué, c'est la chaîne : IaC, orchestration, CI/CD, contrôles de sécurité, observabilité.

## Décision

L'application se limite à une API FastAPI de trois ressources (`/health`, `/items`, `/metrics`)
et à un dashboard React d'une page. Aucune base de données, aucune authentification, stockage
en mémoire.

## Conséquences

- Tout le budget temps va dans la chaîne de sécurité, pas dans le produit.
- L'application reste une cible crédible pour SAST, SCA, scan d'image, DAST et admission control.
- Toute évolution fonctionnelle au-delà de trois endpoints est refusée par défaut ; elle
  nécessite un nouvel ADR.
