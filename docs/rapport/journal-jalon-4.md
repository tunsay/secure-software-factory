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

## 4b — ce qui entre dans le build est figé

### Vérifications faites avant d'écrire (03/10)

| # | Constat | Conséquence |
|---|---|---|
| V6 | Digests courants : `python:3.14-slim` `sha256:0741d101…` (publié le 01/10), `node:24-alpine` `sha256:ebfe2f90…` (18/09), `nginx-unprivileged:stable-alpine3.24` `sha256:ed04ec1f…` (28/09). | Deux ont moins de 7 jours. Épinglés quand même : ce sont **ceux que la CI a utilisés** pour les images signées du jour — le Dockerfile décrit ainsi ce qui est en production. Les mises à jour passeront par Dependabot, avec délai de carence. |
| V7 | `pip-tools` 7.6.1 (12/08) passe le délai de carence. | Utilisé pour générer `requirements.txt` avec empreintes. |
| V8 | `pip-audit --require-hashes -r requirements.txt` audite la liste figée **sans résoudre les dépendances** (README de pip-audit 2.10.1). | ~~Plus de téléchargement depuis PyPI, plus de dépendance à la version de Python du poste.~~ **Conclusion fausse**, démentie par l'essai : voir J4-I5. |
| V9 | pip active la vérification d'empreintes pour **toute** une installation dès qu'un fichier en contient. `requirements-dev.txt` incluait `requirements.txt` et ses outils n'ont pas d'empreintes. | Deux installations séparées : application avec empreintes, puis outils. |
| V10 | Le miroir GitLab testait l'API en **Python 3.12**, GitHub et l'image en 3.14. | Aligné sur la même image que la production, épinglée par digest. |

### J4-I3 — N'importe quel job du workflow pouvait signer en notre nom

- **Trouvé en relisant `ci.yml`**, pas par un outil. Les permissions étaient déclarées au niveau
  du **workflow** :
  ```yaml
  permissions:
    contents: read
    security-events: write
    packages: write        # push des images vers ghcr.io
    id-token: write        # token OIDC — Cosign keyless
  ```
  Donc **chaque job** pouvait demander un jeton OIDC à GitHub, y compris `api` et `web`, qui
  exécutent du code tiers (`pip install`, `npm ci` et les scripts d'installation des paquets
  npm). Ce jeton porte l'identité `ci.yml@refs/heads/main` — **exactement celle qu'exige la
  vérification** de 4a. Un paquet compromis dans un de ces jobs aurait pu signer une image
  malveillante, et `make supply-chain-proof` aurait répondu OUI.
- **Ce que ça montre** : la signature de 4a prouve « signé par ce workflow », pas « signé par
  l'étape de publication ». La garantie ne vaut que si l'identité est réservée à l'étape qui doit
  l'utiliser.
- **Correction** (moindre privilège) : au niveau du workflow, `contents: read` seulement. Droits
  accordés job par job : `security-events: write` aux trois jobs qui envoient un SARIF (semgrep,
  iac, images) ; `packages: write` et `id-token: write` **au seul job `images`**, qui n'exécute
  sur le runner que des actions épinglées par SHA, jamais `pip install` ni `npm ci` (les
  dépendances s'installent dans la construction de l'image, sans accès aux jetons).
- **Preuve** : nouveau test de `make supply-chain-proof` (« qui peut obtenir un jeton OIDC ? »),
  et, plus parlant, la section `GITHUB_TOKEN Permissions` du journal de chaque job en CI, avant
  et après.
- **Leçon** : une signature sans clé déplace la question de la clé vers l'identité. Protéger
  l'identité, c'est limiter **qui, dans le pipeline, peut l'obtenir**.

### Ce qui a été construit

| Fichier | Changement |
|---|---|
| `.github/workflows/ci.yml` | permissions au moindre privilège (J4-I3) ; installation de l'application avec `--require-hashes` ; `pip-audit --require-hashes` ; contrôle des dérogations dans le job gitleaks |
| `app/api/Dockerfile`, `app/web/Dockerfile` | 4 images de base épinglées par digest ; `pip install --require-hashes` |
| `app/api/requirements.in` (nouveau) | les 4 dépendances directes, seule liste modifiée à la main |
| `app/api/requirements.txt` | à régénérer : toutes les dépendances, avec empreintes, résolues en Python 3.14 |
| `app/api/requirements-dev.txt` | n'inclut plus `requirements.txt` (V9) |
| `scripts/check-exceptions.py` (nouveau) | échoue si une dérogation est expirée ou sans date ; bibliothèque standard seulement |
| `security/exceptions.yaml` | la dérogation gitleaks de J4-I1 y est aussi inscrite, avec expiration |
| `.gitlab-ci.yml` | même image Python que la production (V10), mêmes installations, contrôle des dérogations |
| `Makefile` | venv local depuis `requirements.in` (poste en 3.10, voir J4-I2) ; `make scan` audite avec empreintes et contrôle les dérogations |
| `scripts/supply-chain-proof.sh` | test « qui peut signer en notre nom ? » |

Compromis assumé : le venv **local** (Python 3.10) n'impose pas les empreintes, car la liste est
résolue pour 3.14. Il sert aux tests et au lint ; tout ce qui mène à la production (construction
de l'image, CI) les impose.

### « Avant » des permissions, lu dans le journal réel de la CI

Run 37130165106, job `api` (qui installe et teste des paquets, ne publie rien) :
```
GITHUB_TOKEN Permissions
Contents: read
Metadata: read
Packages: write
SecurityEvents: write
```
Le sur-privilège est confirmé (`Packages: write` sur un job qui ne publie jamais). Correction
d'une affirmation faite trop vite : `IdToken` **n'apparaît pas** dans cette section, qui ne liste
que les droits du `GITHUB_TOKEN`. Le droit `id-token: write` était pourtant bien accordé à ce job
(même bloc au niveau du workflow, celui que le job `images` utilisait pour signer).

### `requirements.txt` avec empreintes

Généré dans l'image de production (Python 3.14, digest épinglé), avec pip-tools 7.6.1 :
**21 paquets figés, 515 empreintes**, aucun paquet écarté comme « unsafe ». Contre-vérification :
le SBOM signé de l'image api listait exactement **21 bibliothèques Python** — la liste figée est
celle qui est en production.

### J4-I4 — Docker ne peut plus télécharger d'image publique depuis WSL

- **Symptôme** : `docker run python:3.14-slim@sha256:…` →
  `docker: error getting credentials - err: exit status 1, out: ``` — rien n'est téléchargé.
- **Cause** : avant tout téléchargement, le client Docker de WSL interroge l'assistant
  d'identifiants de Docker Desktop (programme Windows), qui échoue sans message. Problème connu
  de l'intégration WSL. L'image est publique : aucun identifiant n'est nécessaire.
- **Contournement, sans toucher à la configuration** : pour la seule commande de téléchargement,
  un dossier de configuration Docker vide et temporaire (`DOCKER_CONFIG=$(mktemp -d) docker pull
  …`) : téléchargement anonyme, digest vérifié `sha256:0741d101…`. Une fois l'image locale, la
  commande suivante n'a plus besoin d'identifiants.
- **Leçon** : un environnement de poste accumule des composants (assistants d'identifiants,
  relais réseau) qui peuvent casser un geste simple. Contourner pour une commande, sans modifier
  la configuration de l'utilisateur.
- **Second accroc du même genre**, juste après : `make: getcwd: No such file or directory`. Le
  shell WSL avait perdu sa référence au dossier courant sur `/mnt/c` (le dossier existait bien,
  lisible depuis Windows) après une activité Docker intense. Correction : y revenir (`ssf`, l'alias
  créé au jalon 3). Rien de perdu ni de modifié.

### Validation locale du 4b, premier passage (`make scan`)

- **Les deux images se construisent** avec les bases épinglées par digest ; dans l'api,
  `pip install --require-hashes` passe : les 21 paquets sont dans l'image.
- **Trivy : 0** sur l'api (87 paquets Debian, et les **21 paquets Python** analysés un par un)
  et **0** sur le web (70 paquets Alpine).
- **`pip-audit` échoue** : voir J4-I5.

### J4-I5 — `pip-audit --require-hashes` dépend quand même du Python du poste

- **Symptôme** (`make scan`, poste en Python 3.10) :
  ```
  ERROR:pip_audit._virtual_env:internal pip failure: ERROR: Ignored the following versions that
    require a different python version: 17.0 Requires-Python >=3.11; ... 17.1 Requires-Python >=3.11
  ERROR: Could not find a version that satisfies the requirement websockets==17.1
  ```
- **Cause** : contrairement à ce qui avait été écrit en V8, `--require-hashes` évite la
  **résolution** des dépendances, mais pip-audit continue d'appeler `pip install --dry-run`
  dans un environnement temporaire créé avec le **Python local** (3.10) — qui ne peut pas
  installer `websockets 17.1` (Python ≥ 3.11), figé pour la 3.14.
- **Correction** : `--disable-pip` (documenté : « ne pas utiliser pip ; possible uniquement avec
  un fichier à empreintes ou `--no-deps` »). pip-audit lit les versions figées et interroge
  directement la base de vulnérabilités. Appliqué au Makefile, à GitHub et à GitLab, pour que les
  trois exécutent le même contrôle. La vérification des empreintes reste là où elle protège : à
  l'installation, dans la construction de l'image.
- **Leçon** : lire une option dans une documentation ne suffit pas à savoir ce qu'elle fait ;
  l'essai a démenti l'interprétation. Écrire « vérifié » seulement après l'avoir vu s'exécuter.

### J4-I6 — Les clés privées du cluster, en clair dans le dossier du projet depuis 15 jours

- **Symptôme** : `make scan`, après correction de J4-I5, échoue sur `gitleaks dir .` :
  `leaks found: 6`. Détail (`--verbose`, secrets masqués) :
  ```
  RuleID: private-key   File: infra/terraform/cluster/terraform.tfstate                    Line: 35, 89
  RuleID: private-key   File: infra/terraform/cluster/terraform.tfstate.backup             Line: 35, 89
  RuleID: private-key   File: infra/terraform/cluster/terraform.tfstate.1789741825.backup  Line: 35, 91
  ```
- **Hypothèse initiale, fausse** : des fausses clés de test dans le venv ou `node_modules`
  reconstruits. Ce sont des **vraies** clés : l'identité administrateur du cluster kind, que le
  provider `tehcyx/kind` écrit en clair dans l'état Terraform local de la couche cluster (même
  cause que l'incident I2 du jalon 3), plus les copies de sauvegarde de Terraform.
- **Portée, vérifiée** :
  - fichiers **ignorés par git** (`.gitignore` : `*.tfstate`, `*.tfstate.*`), présents dans
    **aucun commit** (`git log --all` sur ces chemins : 0) — jamais poussés, jamais vus par la CI ;
  - sur le disque depuis le **18/09** (jalon 2), dans le dossier du projet, sur le disque
    Windows ;
  - clés d'un cluster local joignable sur 127.0.0.1 seulement ; celles des sauvegardes appartiennent
    à des clusters déjà détruits.
- **C'est un vrai positif, et un rappel** : `make scan` complet n'avait pas été rejoué depuis le
  jalon 2. Il l'aurait signalé dès la création du cluster. `.gitignore` empêche de **publier** un
  secret ; il ne l'empêche pas d'**exister** en clair à côté du code.
- **Correction** : pas d'exclusion du scan (ce serait masquer un vrai secret). L'état de la couche
  cluster sort du dépôt : backend `local` avec un chemin passé à l'init,
  `~/.local/state/ssf/cluster.tfstate`, dans le dossier personnel WSL (système de fichiers Linux,
  dossier en droits 700). Le kubeconfig, qui porte la même clé, y était déjà (`~/.kube/ssf-dev`).
  Migration unique de l'état existant (`terraform init -migrate-state`), puis suppression des trois
  fichiers du dossier du projet.
- **Leçon** : un secret ignoré par git reste un secret sur le disque. Ranger les états Terraform
  qui contiennent des identifiants hors de l'arborescence du code, là où aucun outil de partage,
  de sauvegarde ou de recherche du poste ne les ramassera par accident.
- **Migration** (03/10) : `terraform init -migrate-state` → « copier l'état existant ? » `yes` ;
  `terraform state list` → `kind_cluster.this` ; `terraform plan -detailed-exitcode` → **code 0**
  (aucun écart avec le cluster réel ; sortie jetée volontairement, pour qu'un éventuel écart
  n'affiche pas la clé, cf. I2) ; fichier dans `~/.local/state/ssf/`, dossier en `drwx------`.
  Puis suppression des trois fichiers du dossier du projet.

### Validation locale du 4b, passage complet (`make scan`, puis `make supply-chain-proof`)

- Images : construction OK, Trivy **0** / **0**.
- `pip-audit --require-hashes --disable-pip` : `No known vulnerabilities found`.
- `npm audit` : 0. Dérogations : `3 dérogation(s), aucune expirée`.
- `gitleaks dir` : **no leaks found** (J4-I6 corrigé). `gitleaks git` : **24 commits**, no leaks.
- Preuve : images de base **4/4**, **515 empreintes**, contrôle des dérogations en place.

### J4-I7 — Le test « qui peut signer ? » se trompait lui-même

- **Symptôme** : `NON      jobs concernés : images, images`.
- **Cause** : le test cherchait la chaîne `id-token: write` n'importe où dans le fichier. Il l'a
  trouvée deux fois dans le job `images` : la vraie permission, et un **commentaire** écrit dans
  le même job (« …l'identité OIDC de ce workflow (id-token: write)… »). La configuration était
  juste ; le test, faux.
- **Correction** : seule une **clé YAML en début de ligne** compte, et chaque job une seule fois.
- **Leçon** : un test de sécurité est du code, il a ses propres bugs. Ici le défaut était un faux
  NON, visible ; le cas dangereux est le faux OUI. D'où la double vérification du test corrigé :
  sur l'**ancien** `ci.yml` (dernier commit, il doit répondre NON) et sur le **nouveau** (OUI).
  Résultat :
  ```
  == ancien ci.yml (dernier commit)
  NON      accordé à tout le workflow : chaque job, y compris ceux qui installent des paquets tiers
  == nouveau ci.yml (copie de travail)
  OUI      seul le job images (publication), qui n'installe aucun paquet sur le runner
  ```
  Le test distingue les deux configurations : on peut s'y fier.

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

### J4-I2 — `pip-audit` échoue en CI… sur une coupure réseau

- **Symptôme** : commit `0f523a1` (déploiement par digest), run `ci` 37130165106 en échec, job
  `api`, étape `pip-audit (SCA)`. Publication des images en `skipped`. Le workflow `e2e` du même
  commit est vert.
- **Première hypothèse, fausse** : une nouvelle vulnérabilité publiée, comme l'incident I9 du
  jalon 3. Mais en local, la même commande ne trouve rien :
  ```
  $ app/api/.venv/bin/pip-audit -r app/api/requirements.txt --strict --desc on
  No known vulnerabilities found
  code retour : 0
  ```
- **Diagnostic** (journal de l'étape en échec, filtré : `gh run view --log-failed | grep ...`) :
  ```
  WARNING: Retrying (Retry(total=4, ...)) after connection broken by
    'ConnectionResetError(104, 'Connection reset by peer')': /packages/.../platformdirs-4.12.2-py3-none-any.whl.metadata
  requests.exceptions.ConnectionError: ('Connection aborted.', ConnectionResetError(104, 'Connection reset by peer'))
  ##[error]Process completed with exit code 1.
  ```
  `pip-audit` doit télécharger les métadonnées des paquets depuis PyPI ; la connexion entre le
  runner et PyPI a été coupée, quatre tentatives ont échoué. Panne réseau passagère, pas une
  faille.
- **Comportement correct de la chaîne** : quand le contrôle **ne peut pas vérifier**, il échoue,
  et la publication est bloquée (*fail-closed*). « Je n'ai pas pu contrôler » vaut « refusé ».
  L'inverse — laisser passer quand le contrôle ne s'exécute pas — serait un trou.
- **Correction** : relancer les jobs en échec (`gh run rerun --failed`), aucune modification de
  code. Tentative 2 du run 37130165106 : `pip-audit` vert, puis publication, SBOM, signature et
  vérification des deux images, `completed success`. Le diagnostic « panne réseau » est confirmé
  par la contre-épreuve.
- **Écart d'environnement relevé au passage** : le venv local tourne en **Python 3.10**
  (`python3` de WSL, paquets `cp310`), la CI et l'image en **3.14**. Un contrôle local peut donc
  résoudre d'autres versions de dépendances que la CI. Même famille que Node 22 / 24 (jalon 3).
- **Leçon** : deux échecs de même forme (CI rouge sur un contrôle de dépendances, code inchangé)
  peuvent avoir des causes opposées. Une vulnérabilité se corrige ; une panne se relance. Seul le
  journal de l'étape tranche.
