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

### Premier run (commit `ef53ba8`, run `ci` 37129434098) : tout vert du premier coup

Dans les deux jobs `build + trivy`, toutes les nouvelles étapes en `success` : publication de
l'image scannée (contrôle `config.digest` compris), SBOM, signature, attestation, vérification.
Images publiées et signées :

```
ssf-api:ef53ba87374d630f3d5db367d845589c765bb405@sha256:783f41b69d1bf948dacf673a465165a4ba8a293367d38d1206125ff35f83b2c5
ssf-web:ef53ba87374d630f3d5db367d845589c765bb405@sha256:d84eb2cbe363073fd2e42b604276484cc7038841407a1160755661868e15c01b
```

**Où cosign v3 range la signature sur GHCR** (vérifié par l'API du registre, sans
authentification) :
- l'API OCI 1.1 « referrers » n'est pas prise en charge par GHCR :
  `GET /v2/tunsay/ssf-api/referrers/sha256:783f…` → `MANIFEST_UNKNOWN` ;
- cosign utilise donc le **schéma de repli** : un tag `sha256-<digest de l'image>`, qui désigne un
  index OCI contenant **deux bundles Sigstore** (`application/vnd.dev.sigstore.bundle.v0.3+json`) :
  la signature et l'attestation du SBOM.
- **À vérifier au jalon 5** : Kyverno doit savoir lire des bundles v0.3 rangés selon ce schéma.

## 4a, étape 2 — le cluster déploie par digest

| Fichier | Changement |
|---|---|
| `platform/variables.tf` | nouvelle variable `image_digests` (`api`, `web`), validée : `sha256:` + 64 caractères hexadécimaux |
| `platform/dev.tfvars` | images de `ef53ba8`, tag **et** digests repris du résumé du job CI |
| `platform/app.tf` | les digests passent au chart |
| `k8s/chart/templates/_helpers.tpl` | image = `dépôt:tag@digest` ; le chart **refuse** une image sans digest valide |
| Makefile, CI GitHub, CI GitLab | `chart-lint` passe aussi les digests lus dans `dev.tfvars` |

Le tag reste dans la référence pour la lecture humaine ; au tirage, seul le digest compte.

Validation (03/10) : `make infra-lint` vert (chart rendu avec les digests, trivy **0** ;
`terraform fmt` sans écart, `validate` ×3, Checkov silencieux, trivy **0**). Plan :
`0 to add, 1 to change, 0 to destroy` — seul `helm_release.app` change : `tag` 8a5d1dc → ef53ba8,
`digests` ajoutés, `chartChecksum` modifié.

## APRÈS 4a — `make supply-chain-proof` (03/10, images de `ef53ba8` déployées par digest)

```
cosign : v3.1.3

############ CE QUI EST DÉPLOYÉ ############

== api : ghcr.io/tunsay/ssf-api:ef53ba87374d630f3d5db367d845589c765bb405@sha256:783f41b69d1bf948dacf673a465165a4ba8a293367d38d1206125ff35f83b2c5
-- signée par le workflow ci de ce dépôt, sur main ?
OUI      signature valide, identité vérifiée
-- SBOM CycloneDX signé, attaché à l'image ?
OUI      2812 composants décrits
-- référence immuable (digest) ?
OUI      épinglée par digest : le contenu ne peut pas changer

== web : ghcr.io/tunsay/ssf-web:ef53ba87374d630f3d5db367d845589c765bb405@sha256:d84eb2cbe363073fd2e42b604276484cc7038841407a1160755661868e15c01b
-- signée par le workflow ci de ce dépôt, sur main ?
OUI      signature valide, identité vérifiée
-- SBOM CycloneDX signé, attaché à l'image ?
OUI      1282 composants décrits
-- référence immuable (digest) ?
OUI      épinglée par digest : le contenu ne peut pas changer

############ LA VÉRIFICATION FAIT-ELLE LA DIFFÉRENCE ? ############

== image d'avant le jalon 4, jamais signée (doit être REFUSÉE)
REFUSÉE  error during command execution: no signatures found

== image api déployée, en exigeant une autre identité, le workflow e2e (doit être REFUSÉE)
REFUSÉE  failed to verify certificate identity: no matching CertificateIdentity found, last error: expected SAN value "https://github.com/tunsay/secure-software-factory/.github/workflows/e2e.yml@refs/heads/main", got "https://github.com/tunsay/secure-software-factory/.github/workflows/ci.yml@refs/heads/main"
```

Puis `make app-proof` vert : pods redémarrés avec les images signées, application servie,
processus non-root, système de fichiers en lecture seule.

Lecture :
- **Les six réponses de 4a passent de NON à OUI.**
- **Le dernier refus est le plus important** : l'image *est* signée, et pourtant elle est refusée,
  parce que la signature vient du workflow `ci` et que l'on exigeait `e2e`. Au « avant », ce test
  était refusé faute de toute signature ; il refuse maintenant pour la bonne raison. Une signature
  valide ne suffit pas, il faut **la bonne identité** : c'est ce qui arrête une signature produite
  depuis un fork, une autre branche ou un autre workflow.
- La partie « ce qui entre dans le build » reste à NON : c'est l'objet du jalon 4b.

### Que contiennent ces SBOM ? (SBOM signé, déballé et compté par type)

Avant d'écrire « 2812 composants » dans un rapport, vérifier ce que le chiffre recouvre : la
commande vérifie l'attestation (même règle que la preuve), décode le SBOM et compte les
composants CycloneDX par type.

```
== api
  2702  file               -
    87  library            deb
    21  library            python
     1  application        binary
     1  operating-system   -
== web
  1211  file               -
    70  library            apk
     1  operating-system   -
```

- Le gros des chiffres est l'**inventaire des fichiers**. L'information utile pour la sécurité,
  ce sont les **paquets** : 87 Debian + 21 Python (pour 4 dépendances directes) + l'interpréteur
  pour l'api ; 70 Alpine pour le web.
- **Angle mort découvert** : le SBOM du web ne liste **aucune bibliothèque JavaScript**, alors
  que React y est. Vite **regroupe** React et ses dépendances dans un seul fichier
  `index-*.js` : vu depuis l'image, c'est un fichier, pas des bibliothèques. Un scanner qui ne
  regarde que l'image ne verrait pas une faille de React. Pour la couvrir : un SBOM du **code
  source** (depuis `package-lock.json`), attesté lui aussi. Aujourd'hui, ces dépendances sont
  contrôlées en amont par `npm audit` (job `web`), mais pas inventoriées avec l'image.
- **Leçon** : un SBOM n'est exhaustif que pour ce que l'outil sait reconnaître. Le mot
  « exhaustif » du plan initial était trop fort ; il faut savoir ce qu'un SBOM ne voit pas.

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
- **Vérification du vérificateur** : un faux secret écrit hors du dépôt (`/tmp`), analysé avec
  la nouvelle configuration :
  ```
  $ gitleaks dir /tmp/temoin-secret.txt --config .gitleaks.toml --no-banner --redact
  WRN leaks found: 1
  code retour : 1
  ```
  Les règles par défaut restent actives. Puis commit `ef53ba8` : hook gitleaks `Passed`.
- **Pourquoi pas une exclusion de fichier** : le script et le journal doivent rester analysés
  (incident I5 du jalon 3 : un document peut contenir un secret).
- **Leçon** : un nom de composant (`ssf-api`) peut suffire à déclencher une règle heuristique.
  Un faux positif se traite par une exception étroite et justifiée, jamais en élargissant le
  trou.
