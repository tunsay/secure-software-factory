# Chapitre 4 — Jalon 4 : la chaîne d'approvisionnement

*3 octobre 2026 — signer ce qui est publié, figer ce qui entre dans le build, et découvrir que
n'importe quel job pouvait signer en notre nom*

## Objectif du jalon

Au jalon 3, le cluster exécute des images désignées par un **tag**. Rien ne prouve d'où elles
viennent, rien ne dit ce qu'elles contiennent, et le tag peut être déplacé dans le registre. Le
build lui-même tire des versions mobiles : `python:3.14-slim` désigne une image différente chaque
semaine, pip installe ce que l'index lui sert.

Deux livrables :

- **4a — ce qui est publié est signé et décrit** : SBOM, signature sans clé, SBOM signé et attaché
  à l'image, publication de l'image exacte qui a été scannée, déploiement par digest ;
- **4b — ce qui entre dans le build est figé** : images de base par digest, dépendances Python
  vérifiées par empreinte, contrôle d'expiration des dérogations de sécurité.

Même méthode qu'aux jalons 2 et 3 : une commande, `make supply-chain-proof`, lancée **avant** et
**après**, en lecture seule.

## Ce qui a été vérifié avant d'écrire

- **cosign v3.1.3**, signature *sans clé* : l'identité est celle du workflow, attestée par le
  jeton OIDC de GitHub. Aucune clé à garder, à faire tourner, ni à laisser fuiter.
- **Délai de carence de 7 jours** appliqué aux outils épinglés, comme Dependabot le fait pour les
  dépendances : syft v1.54.0 avait deux jours, c'est la v1.52.0 qui est retenue.
- **cosign v3 a changé de format** : la signature est un artefact OCI 1.1 rattaché à l'image, non
  plus un tag `.sig`. Les tutoriels en ligne sont majoritairement en v2.
- **L'image publiée n'était pas celle qui avait été scannée** : l'étape de publication
  reconstruisait l'image depuis le cache. Corrigé avant même de signer quoi que ce soit.

## 4a — Signer ce qui est publié ([ADR 0010](../adr/0010-signature-sans-cle-et-sbom.md))

Dans le job de publication, sur `main` uniquement, après tous les contrôles :

| Étape | Ce qu'elle garantit |
|---|---|
| Publier l'image **chargée et scannée**, sans reconstruction, puis vérifier que sa configuration est celle de l'image scannée | on publie exactement ce qui a été contrôlé |
| SBOM CycloneDX (Syft) de l'image publiée | l'inventaire de ce qui est en production |
| `cosign sign` sur le **digest** | preuve d'origine, liée au contenu exact |
| `cosign attest` du SBOM | l'inventaire voyage avec l'image et ne peut pas être modifié sans être détecté |
| `cosign verify` + `verify-attestation`, identité **exacte** | la règle d'acceptation est testée dès la publication |

L'identité exigée n'est pas une expression large mais une valeur exacte :
`https://github.com/tunsay/secure-software-factory/.github/workflows/ci.yml@refs/heads/main`.

GHCR ne prend pas en charge l'API OCI 1.1 « referrers » : cosign v3 range alors la signature et
l'attestation dans un tag `sha256-<digest de l'image>` qui désigne un index de deux *bundles*
Sigstore. Vérifié directement dans le registre ; à garder en tête pour Kyverno au jalon 5.

Le cluster déploie ensuite par `dépôt:tag@digest` : le tag reste lisible, seul le digest fait foi,
et le chart **refuse** une image sans digest valide.

## 4b — Figer ce qui entre dans le build

| Mesure | Avant | Après |
|---|---|---|
| Images de base | `python:3.14-slim`, `node:24-alpine`, `nginx-unprivileged:stable-alpine3.24` : tags mobiles | **épinglées par digest** ; Dependabot propose les mises à jour |
| Dépendances Python | 4 versions directes ; le reste résolu au moment du build | `requirements.in` → `requirements.txt` : **21 paquets, 515 empreintes**, installés avec `--require-hashes` |
| Dérogations de sécurité | « une dérogation expirée fait échouer la CI » écrit depuis le jalon 1, jamais contrôlé | `scripts/check-exceptions.py`, en CI et dans `make scan` |
| Droits des jobs CI | `packages` et `id-token` en écriture pour **tout** le workflow | **seul le job de publication** peut publier et signer ([ADR 0011](../adr/0011-moindre-privilege-des-jobs-ci.md)) |

Contre-vérification : le SBOM signé de l'image api listait **21 bibliothèques Python** ; la liste
figée par empreintes en contient exactement **21**. Ce qui est figé est ce qui est en production.

`requirements.txt` est résolu **dans l'image de production elle-même** (Python 3.14, digest
épinglé) : les dépendances conditionnelles à la version de Python sont celles de l'image, pas
celles du poste.

## Avant / après — de quoi on est protégé

**Avant** (mesuré le 3 octobre, images de `8a5d1dc`) :

```
== api : ghcr.io/tunsay/ssf-api:8a5d1dc21ae57640f61dd66d470ad5a37470d208
NON      error during command execution: no signatures found
NON      error during command execution: no matching attestations:
NON      tag seul : ce qu'il désigne peut être remplacé dans le registre
...
== images de base épinglées par digest
0/4
== dépendances Python vérifiées par empreinte (--require-hashes)
NON      aucune empreinte : pip installe ce que l'index lui sert
== dérogations de sécurité expirées détectées (security/exceptions.yaml)
NON      aucun contrôle : une dérogation expirée reste active indéfiniment
```

**Après** (images de `f159b94`, entièrement durcies) :

```
== api : ghcr.io/tunsay/ssf-api:f159b944b9f7b2b4e2ffb87c2fe6b097fdc1a24a@sha256:a0269bc4f1a0674940d19a8ecd6b189e41680fbda4820383d66b62dfed8f6ef7
OUI      signature valide, identité vérifiée
OUI      2812 composants décrits
OUI      épinglée par digest : le contenu ne peut pas changer
...
== jobs de ci.yml autorisés à obtenir un jeton OIDC (id-token: write)
OUI      seul le job images (publication), qui n'installe aucun paquet sur le runner
== images de base épinglées par digest
4/4
== dépendances Python vérifiées par empreinte (--require-hashes)
OUI      515 empreintes dans app/api/requirements.txt
== dérogations de sécurité expirées détectées (security/exceptions.yaml)
OUI      contrôle en place : 3 dérogation(s), aucune expirée
```

| Question | Avant | Après |
|---|---|---|
| Les images déployées sont-elles signées par la CI de ce dépôt, sur `main` ? | non | **oui** |
| Un SBOM signé est-il attaché à l'image ? | non | **oui** |
| Le cluster désigne-t-il un contenu immuable ? | non, un tag | **oui, un digest** |
| L'image publiée est-elle celle qui a été scannée ? | non, une reconstruction | **oui, vérifié en CI** |
| Qui, dans la CI, peut signer en notre nom ? | **tous les jobs** | **le seul job de publication** |
| Les images de base sont-elles figées ? | 0/4 | **4/4** |
| Les paquets Python sont-ils vérifiés à l'installation ? | non | **oui, 515 empreintes** |
| Une dérogation expirée est-elle détectée ? | non | **oui** |

### La vérification fait la différence

Deux tests de contrôle, refusés avant **et** après — mais pas pour la même raison :

```
== image d'avant le jalon 4, jamais signée (doit être REFUSÉE)
REFUSÉE  error during command execution: no signatures found

== image api déployée, en exigeant une autre identité, le workflow e2e (doit être REFUSÉE)
REFUSÉE  failed to verify certificate identity: no matching CertificateIdentity found, last error:
         expected SAN value ".../workflows/e2e.yml@refs/heads/main",
         got ".../workflows/ci.yml@refs/heads/main"
```

Le second est le plus important. Avant, il était refusé faute de toute signature. Après, l'image
**est** signée, et elle est pourtant refusée : la signature vient du workflow `ci`, on exigeait
`e2e`. **Une signature valide ne suffit pas, il faut la bonne identité** — c'est ce qui arrête une
signature produite depuis un fork, une autre branche ou un autre workflow.

### Ce que les SBOM voient… et ne voient pas

SBOM signé, déballé et compté par type :

| | api | web |
|---|---|---|
| Fichiers inventoriés | 2702 | 1211 |
| Paquets système | 87 (Debian) | 70 (Alpine) |
| Bibliothèques Python | 21 | — |
| **Bibliothèques JavaScript** | — | **0** |

Le web n'affiche **aucune** bibliothèque JavaScript, alors que React y est : Vite le regroupe avec
ses dépendances dans un seul fichier `index-*.js`. Vu depuis l'image, c'est un fichier, pas une
bibliothèque. Un scanner qui ne regarde que l'image ne verrait pas une faille de React. Les
dépendances npm restent contrôlées en amont (`npm audit`), mais elles ne sont pas inventoriées
avec l'image : il faudrait un SBOM du **code source**, attesté lui aussi. Un SBOM n'est exhaustif
que pour ce que l'outil sait reconnaître.

## Ce qui a cassé, et ce que ça a appris

Sept incidents. Aucun dans le code de l'application. Détail dans le
[journal du jalon](journal-jalon-4.md).

**1. gitleaks prend un SHA de commit pour une clé d'API.** `ssf-api:8a5d1dc…` : le mot `api` suivi
de 40 caractères hexadécimaux a la forme d'une clé. Exception **étroite** (une ligne portant le tag
d'une de nos images), écrite pour les deux versions de gitleaks en service, puis vérifiée par un
faux secret témoin : les règles par défaut détectent toujours.
*Leçon : un faux positif se traite par une exception étroite et justifiée, jamais en élargissant
le trou — et l'on vérifie que le détecteur détecte encore.*

**2. `pip-audit` échoue en CI… sur une coupure réseau.** Même forme qu'une vulnérabilité publiée
(incident I9 du jalon 3), cause opposée : `Connection reset by peer` vers PyPI. Le contrôle, faute
de pouvoir vérifier, a **bloqué** la publication. Relance, vert.
*Leçon : « je n'ai pas pu contrôler » doit valoir « refusé ». Et seul le journal de l'étape dit
s'il faut corriger ou relancer.*

**3. N'importe quel job du workflow pouvait signer en notre nom.** Trouvé en relisant `ci.yml`, pas
par un outil : `id-token: write` accordé au workflow entier. Un paquet compromis dans le job `api`
ou `web` aurait obtenu un jeton à l'identité `ci.yml@main` — celle qu'exige la vérification — et
signé une image malveillante, que la preuve aurait déclarée « OUI ». Corrigé par le moindre
privilège, job par job, prouvé par le journal réel de la CI.
*Leçon : une signature sans clé déplace la question de la clé vers l'identité. Protéger
l'identité, c'est limiter qui, dans le pipeline, peut l'obtenir.*

**4. Docker ne télécharge plus d'image publique depuis WSL.** L'assistant d'identifiants de Docker
Desktop échoue sans message. Contourné pour une seule commande par un dossier de configuration
vide et temporaire, sans toucher à la configuration du poste.

**5. `pip-audit --require-hashes` dépend quand même du Python du poste.** Une option lue dans la
documentation (« sans résolution de dépendances ») a été interprétée trop vite : pip-audit appelait
toujours pip, avec le Python 3.10 du poste, incapable d'installer `websockets 17.1`. Corrigé par
`--disable-pip`, appliqué partout.
*Leçon : écrire « vérifié » seulement après l'avoir vu s'exécuter.*

**6. Les clés privées du cluster, en clair dans le dossier du projet depuis quinze jours.** `make
scan` complet, rejoué pour la première fois depuis le jalon 2 : gitleaks trouve l'identité
administrateur du cluster dans l'état Terraform local et ses sauvegardes. Ignorés par git, présents
dans aucun commit — jamais publiés — mais en clair à côté du code. L'état est déplacé hors du dépôt
(`~/.local/state/ssf/`, droits 700), par migration vérifiée.
*Leçon : `.gitignore` empêche de publier un secret, pas de le laisser traîner.*

**7. Le test « qui peut signer ? » se trompait lui-même.** Il comptait la chaîne `id-token: write`
jusque dans un commentaire. Corrigé, puis vérifié dans les deux sens : NON sur l'ancienne
configuration, OUI sur la nouvelle.
*Leçon : un test de sécurité est du code ; il faut l'avoir vu échouer pour lui faire confiance.*

## État en fin de jalon

- Images publiées **telles que scannées**, décrites (SBOM), **signées** et **attestées** par le seul
  job de publication ; vérification en CI à chaque publication.
- Cluster déployé par **digest** ; chart qui refuse une image sans digest.
- Build figé : **4/4** images de base par digest, **515 empreintes** Python.
- Dérogations de sécurité **contrôlées** (3, aucune expirée).
- `make supply-chain-proof` : chaque réponse à OUI, et deux refus pour les bonnes raisons.
- Deux ADR : 0010 (signature sans clé, SBOM), 0011 (moindre privilège des jobs CI).
- Sept incidents documentés, dont un défaut de conception de la signature (3) et un vrai secret sur
  le disque (6), tous deux trouvés pendant le jalon.

## Ce qui reste ouvert, et pourquoi

| Point | Statut | Traitement prévu |
|---|---|---|
| Kyverno doit vérifier les signatures cosign v3 (bundles v0.3, schéma de repli par tag sur GHCR) | à vérifier | jalon 5, avant de s'y appuyer |
| Bibliothèques JavaScript absentes du SBOM du web (code regroupé par Vite) | angle mort connu | SBOM du code source, attesté avec l'image |
| Images d'outils tirées par tag mobile en CI : `semgrep/semgrep`, `bridgecrew/checkov`, images GitLab | ouvert | épingler par digest |
| `apt-get upgrade` / `apk upgrade` dans les Dockerfiles : base figée, paquets système mis à jour au build | compromis assumé | correctifs de sécurité plutôt que reproductibilité au bit près ; le SBOM dit ce qui est entré |
| Fenêtre entre la publication et la signature d'une image | assumé | une image non signée sera refusée à l'admission (Kyverno, jalon 5) |
| 9 PR Dependabot ouvertes, dont `node 25` (non LTS) et deux majeures | à trier | à la main, selon la politique du dépôt |
| Poste en Python 3.10 et Node 22, CI et image en 3.14 et 24 | écart d'environnement | aligner le poste |
| Signatures publiques (journal Rekor) | assumé (dépôt public) | instance Sigstore privée pour un projet privé |
