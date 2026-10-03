# Journal de bord — jalon 4

Notes prises au fil de l'eau, matière première du chapitre `04-jalon-4.md`. Chaque incident :
symptôme, cause, diagnostic, correction, leçon. Chaque livrable : avant / après, et de quoi on
est protégé.

Objectif : prouver l'intégrité de ce qui est déployé, du build au cluster.

- **4a — ce qui est publié est signé et décrit** : SBOM (Syft), signature Cosign sans clé
  (identité OIDC du workflow `ci` sur `main`), SBOM signé et attaché à l'image, publication de
  l'image exacte qui a été scannée, déploiement par digest.
- **4b — ce qui entre dans le build est figé** : images de base par digest, dépendances Python
  vérifiées par empreinte, contrôle d'expiration des dérogations de sécurité.

---

## Vérifications faites avant d'écrire (03/10)

| # | Constat | Conséquence |
|---|---|---|
| V1 | Dernières versions : cosign **v3.1.3** (06/08), action `cosign-installer` **v4.1.2** (07/05), syft **v1.54.0** (01/10), action `sbom-action` **v0.24.3** (02/10). | syft et sbom-action ont moins de 7 jours. |
| V2 | La politique Dependabot du dépôt impose un **délai de carence de 7 jours** (« ne pas être le premier à installer une release »). | Même règle pour les outils épinglés à la main : syft **v1.52.0** (17/09) et sbom-action **v0.24.2** (28/08). |
| V3 | **cosign v3** (première publication : v3.0.1, 08/10/2025) : format de bundle standardisé par défaut, et signatures stockées comme **artefact OCI 1.1 rattaché à l'image** (plus de tag `.sig`). Les tutoriels en ligne sont majoritairement en v2. | Commandes écrites pour la v3. Point à vérifier au jalon 5 : Kyverno doit savoir vérifier ce format. |
| V4 | `ci.yml` accorde déjà `id-token: write` (prévu dès le jalon 1 « pour Cosign keyless ») et `packages: write`. | Aucun droit supplémentaire à ouvrir pour signer. |
| V5 | Aujourd'hui, l'image publiée sur GHCR est **reconstruite** à l'étape de publication (second `build-push-action`), à partir du cache. Ce qui est scanné par Trivy et ce qui est publié sont deux constructions distinctes. | Publier l'image chargée et scannée elle-même, sans reconstruction : on signe exactement ce qui a été contrôlé. |

## Préparation de la preuve

- `scripts/supply-chain-proof.sh`, appelé par `make supply-chain-proof` : **lecture seule**,
  même commande avant et après, sur le modèle de `isolation-proof` (jalon 3).
- Pour chaque image déployée (api, web) : signée par le workflow `ci` de ce dépôt sur `main` ?
  SBOM CycloneDX signé et attaché ? référence par digest ?
- La vérification fait-elle la différence ? Une image d'avant le jalon 4 (jamais signée) doit être
  refusée ; l'image déployée doit être refusée si l'on exige une autre identité (workflow `e2e`).
- Ce qui entre dans le build : images de base par digest, empreintes Python, contrôle des
  dérogations.
- L'identité exigée est exacte, pas une expression large :
  `https://github.com/tunsay/secure-software-factory/.github/workflows/ci.yml@refs/heads/main`.
  Une signature produite depuis une autre branche ou un autre workflow ne passe pas.

## AVANT — `make supply-chain-proof` (03/10, avant tout changement)

```
cosign : v3.1.3

############ CE QUI EST DÉPLOYÉ ############

== api : ghcr.io/tunsay/ssf-api:8a5d1dc21ae57640f61dd66d470ad5a37470d208
-- signée par le workflow ci de ce dépôt, sur main ?
NON      error during command execution: no signatures found
-- SBOM CycloneDX signé, attaché à l'image ?
NON      error during command execution: no matching attestations:
-- référence immuable (digest) ?
NON      tag seul : ce qu'il désigne peut être remplacé dans le registre

== web : ghcr.io/tunsay/ssf-web:8a5d1dc21ae57640f61dd66d470ad5a37470d208
-- signée par le workflow ci de ce dépôt, sur main ?
NON      error during command execution: no signatures found
-- SBOM CycloneDX signé, attaché à l'image ?
NON      error during command execution: no matching attestations:
-- référence immuable (digest) ?
NON      tag seul : ce qu'il désigne peut être remplacé dans le registre

############ LA VÉRIFICATION FAIT-ELLE LA DIFFÉRENCE ? ############

== image d'avant le jalon 4, jamais signée (doit être REFUSÉE)
REFUSÉE  error during command execution: no signatures found

== image api déployée, en exigeant une autre identité, le workflow e2e (doit être REFUSÉE)
REFUSÉE  error during command execution: no signatures found

############ CE QUI ENTRE DANS LE BUILD ############

== images de base épinglées par digest
0/4
         FROM python:3.14-slim AS builder
         FROM python:3.14-slim AS runtime
         FROM node:24-alpine AS builder
         FROM nginxinc/nginx-unprivileged:stable-alpine3.24 AS runtime

== dépendances Python vérifiées par empreinte (--require-hashes)
NON      aucune empreinte : pip installe ce que l'index lui sert

== dérogations de sécurité expirées détectées (security/exceptions.yaml)
NON      aucun contrôle : une dérogation expirée reste active indéfiniment
```

Lecture, du point de vue d'un attaquant qui obtient le droit d'écrire dans le registre (jeton
de CI volé, compte compromis) :

- **Rien ne prouve d'où vient l'image** : il peut publier sa propre image sous le même tag, et
  rien ne la distingue de celle de la CI.
- **Le cluster demande un tag** : le prochain redémarrage de pod tire ce que le tag désigne à cet
  instant, y compris une image remplacée.
- **Rien ne dit ce que contient l'image** : en cas de nouvelle faille publiée (une bibliothèque,
  un paquet système), impossible de savoir sans la retélécharger et la réanalyser si elle est
  concernée.
- **Le build lui-même tire des versions mobiles** : `python:3.14-slim` désigne une image
  différente chaque semaine ; pip installe ce que l'index lui sert, sans vérifier d'empreinte.
- Les deux « REFUSÉE » sont triviaux ici : rien n'est signé, donc tout est refusé. Ils ne
  prendront leur sens qu'après, quand une image signée sera acceptée et les autres refusées.

## 4a, étape 1 — la CI publie, décrit et signe (ADR 0010)

Dans le job `images` de `ci.yml`, sur `main` uniquement, après tous les contrôles :

| Étape | Ce qu'elle fait | Pourquoi |
|---|---|---|
| Publier l'image scannée | `docker tag` + `docker push` de l'image chargée, puis vérification `config.digest` publié = `Id` de l'image scannée | on publie ce qui a été contrôlé, plus une reconstruction (V5) |
| SBOM | `anchore/sbom-action` (syft v1.52.0), CycloneDX, sur l'image publiée par digest | inventaire exact de ce qui est publié |
| Signer | `cosign sign --yes <dépôt>@<digest>` | preuve d'origine, liée au digest |
| Attester le SBOM | `cosign attest --type cyclonedx` | le SBOM voyage avec l'image, infalsifiable |
| Vérifier | `cosign verify` + `verify-attestation`, identité exacte | la règle d'acceptation est testée dès la publication |
| Résumé du job | référence `tag@digest` à reporter dans `dev.tfvars` | le déploiement par digest (étape 2) |

Choix notables :
- **Référence canonique `dépôt@digest`** pour signer et décrire (comprise de tous les outils) ;
  forme `dépôt:tag@digest` pour le déploiement, plus lisible, le tag y étant informatif.
- **Aucune permission ajoutée** : `id-token: write` et `packages: write` existaient (V4).
- **Échec sûr** : si Sigstore est indisponible, l'image publiée reste non signée, donc refusée.

## Incidents

### J4-I1 — gitleaks prend un SHA de commit pour une clé d'API

- **Symptôme** : au commit de l'étape 1, le hook gitleaks échoue (après un `make semgrep`
  silencieux) :
  ```
  Finding:     UNSIGNED="$REGISTRY/ssf-api:REDACTED"
  RuleID:      generic-api-key
  Entropy:     3.574024
  File:        scripts/supply-chain-proof.sh        Line: 19

  Finding:     ...pi : ghcr.io/tunsay/ssf-api:REDACTED
  RuleID:      generic-api-key
  File:        docs/rapport/journal-jalon-4.md      Line: 48
  ```
  Rien n'est commité.
- **Cause** : la règle `generic-api-key` cherche un mot-clé (`api`, `key`, `token`...) suivi d'une
  longue chaîne d'apparence aléatoire. Notre image s'appelle `ssf-api`, et son tag est le SHA
  complet du commit (40 caractères hexadécimaux) : `ssf-api:8a5d1dc…` a exactement la forme d'une
  clé d'API. Jusqu'ici, aucune référence complète d'image n'avait été écrite telle quelle dans un
  fichier ; à partir du jalon 4, elles vont se multiplier (preuves, déploiement par `tag@digest`).
- **Correction** : `.gitleaks.toml` à la racine, lu par les trois exécutions de gitleaks (hook,
  CI, `make scan`). Une seule exception : une ligne contenant `ssf-api:` ou `ssf-web:` suivi de 40
  caractères hexadécimaux. Toutes les règles restent actives partout ailleurs.
- **Deux pièges évités, vérifiés avant d'écrire** :
  - sans `[extend] useDefault = true`, un fichier de configuration **remplace** les règles par
    défaut : gitleaks ne détecterait plus rien, en silence ;
  - deux versions de gitleaks sont en service : v8.21.2 (hook) et v8.24.3 (fixée par
    `gitleaks-action` v3.0.0). La syntaxe récente `[[allowlists]]` (v8.30) aurait été ignorée par
    la v8.21.2 ; la forme `[allowlist]` est comprise par les deux.
- **Pourquoi pas une exclusion de fichier** : le script et le journal doivent rester analysés
  (incident I5 du jalon 3 : un document peut contenir un secret).
- **Leçon** : un nom de composant (`ssf-api`) peut suffire à déclencher une règle heuristique.
  Un faux positif se traite par une exception étroite et justifiée, jamais en élargissant le
  trou.
