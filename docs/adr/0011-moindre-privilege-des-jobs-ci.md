# ADR 0011 — CI : chaque job ne reçoit que les droits dont il a besoin

**Statut** : accepté · **Date** : 2026-10-03 · **Complète** l'ADR 0010

## Contexte

Les permissions du jeton GitHub étaient déclarées au niveau du **workflow** `ci.yml` :
`packages: write` et `id-token: write` valaient pour tous les jobs. Or les jobs `api` et `web`
exécutent du code tiers (`pip install`, `npm ci` et les scripts d'installation des paquets npm).
Un paquet compromis dans l'un d'eux aurait pu obtenir un jeton OIDC portant l'identité
`ci.yml@refs/heads/main` — exactement celle qu'exige la vérification des signatures (ADR 0010) —
et signer une image en notre nom (journal du jalon 4, J4-I3). Le journal réel de la CI montrait
aussi `Packages: write` sur le job `api`.

## Décision

- Niveau workflow : `permissions: contents: read`, rien d'autre.
- Droits accordés **job par job** :
  - `security-events: write` aux trois jobs qui envoient un rapport SARIF (semgrep, iac, images) ;
  - `packages: write` et `id-token: write` **au seul job `images`**, qui publie et signe.
- Le job `images` n'exécute sur le runner que des actions épinglées par SHA, jamais `pip install`
  ni `npm ci` : les dépendances de l'application s'installent dans la construction de l'image,
  qui n'a pas accès aux jetons du job.

## Conséquences

- Une signature valide signifie désormais « produite par l'étape de publication du workflow
  `ci` sur `main` », et plus seulement « par un job quelconque de ce workflow ».
- Prouvé deux fois : par le journal de chaque job en CI (section `GITHUB_TOKEN Permissions`,
  avant / après) et par `make supply-chain-proof` (« qui peut obtenir un jeton OIDC ? »), test
  lui-même vérifié sur l'ancienne et la nouvelle configuration.
- Tout nouveau job doit déclarer ses droits ; par défaut, il ne peut que lire le dépôt.
- Reste ouvert : le job `semgrep` tourne dans l'image `semgrep/semgrep` tirée par tag mobile,
  avec `security-events: write`. Droit limité, mais image à épingler par digest.
