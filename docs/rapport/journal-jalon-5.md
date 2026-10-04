# Journal de bord — jalon 5

Notes prises au fil de l'eau, matière première du chapitre `05-jalon-5.md`. Chaque incident :
symptôme, cause, diagnostic, correction, leçon. Chaque livrable : avant / après, et de quoi on
est protégé.

Objectif : que le cluster **refuse lui-même** ce qui ne vient pas de la chaîne, et qu'il
revienne seul à l'état décrit dans le dépôt.

- **5a — admission** : Kyverno refuse à l'entrée du cluster une image non signée par la CI, d'un
  autre registre, ou désignée par un tag mobile.
- **5b — GitOps** : ArgoCD reprend le déploiement de l'application ; une modification manuelle du
  cluster est annulée automatiquement.

---

## Vérifications faites avant d'écrire (04/10)

| # | Constat | Conséquence |
|---|---|---|
| V1 | Kyverno : dernière version **v1.19.1** (10/09), chart Helm **3.9.1**. Argo CD : **v3.5.3** (14/09), une 3.6 en pré-version. | Délai de carence de 7 jours respecté. |
| V2 | **Kyverno 1.19.1 ne sait pas vérifier les signatures cosign v3 rangées sur GHCR.** Tickets #17363 (régression 1.19.0 sur les bundles v0.3) et #16678 (attestations cosign v3 non vérifiées) : corrigés, mais dans la **1.19.2, non publiée**. PR #16754, **ouverte** : « sur les registres sans API referrers (ex. GHCR), Kyverno écarte les descripteurs du tag de repli → faux *no signatures found* ». C'est exactement notre cas (vu au jalon 4 : GHCR, schéma de repli par tag). | Une règle en mode bloquant aurait refusé **nos propres images**, déclarées « non signées ». Risque annoncé au jalon 4, confirmé avant d'écrire une ligne. |
| V3 | cosign v3.1.3 sait encore signer dans l'**ancien format**, lu par Kyverno depuis des années : option `--new-bundle-format=false` (existe pour `sign` et `attest`, valeur par défaut `true`), **dépréciée** (« sera le seul format pris en charge dans les versions futures »). | Ancien format disponible, mais transitoire. |
| V4 | **Kyverno 1.19 déprécie `ClusterPolicy`**, retrait prévu en 1.20 (~novembre 2026). Remplacée par des types CEL : `ImageValidatingPolicy` (vérification d'images), `ValidatingPolicy` (règles de validation). | Politiques écrites directement dans les nouveaux types : pas de code déprécié qui casse dans un mois. |
| V5 | Schéma de `ImageValidatingPolicy`, lu dans la **CRD de la v1.19.1** (et non dans un résumé, leçon de J4-I1) : `policies.kyverno.io/v1`, `attestors[].cosign.keyless.identities[].{subject,issuer}`, `ctlog.{url,rekorPubKey,...}`, `attestations[].{intoto,referrer}.type`, `validationConfigurations`, `webhookConfiguration`, `matchImageReferences`. | Champs vérifiés avant d'écrire la politique. |
| V6 | Chart Kyverno 3.9.1 : conteneurs **conformes à PSS restricted par défaut** (non-root, capacités retirées, seccomp, système de fichiers en lecture seule), y compris les jobs d'installation. Demandes mémoire ~64 Mi par contrôleur. | Installable dans le namespace `security` (PSS restricted, quota 3 Gi) sans exception. |

### Décision de Tunsay : double signature, transitoire (ADR 0012)

Trois options pesées :
1. **Double signature** : la CI signe dans les deux formats (v3 et ancien) ; Kyverno vérifie
   l'ancien. Transitoire, avec une condition de sortie écrite.
2. Remplacer Kyverno (policy-controller de Sigstore + politiques natives Kubernetes) : plus
   récent, mais s'écarte du plan, et Kyverno est plus connu.
3. Attendre Kyverno 1.19.2 et la fusion du correctif GHCR : date inconnue.

**Retenue : option 1.** Condition de sortie : dès qu'une version publiée de Kyverno vérifie les
bundles cosign v3 sur un registre sans API referrers, retirer l'ancien format.

## Préparation de la preuve

`scripts/admission-proof.sh`, appelé par `make admission-proof` : chaque test soumet un pod au
cluster en **dry-run serveur** — toute la chaîne d'admission s'exécute (PSS, quotas, webhooks),
mais rien n'est créé. Le pod de test respecte PSS restricted : seule l'image change d'un test à
l'autre.

| Test | Image | Attendu après Kyverno |
|---|---|---|
| 1 | l'image qui tourne : signée par la CI, par digest | admise |
| 2 | `ssf-api:8a5d1dc…`, publiée avant le jalon 4, jamais signée, par tag | refusée |
| 3 | la même, par digest (`sha256:95dc3cb0…`) | refusée |
| 4 | `busybox:1.37` de Docker Hub, par digest | refusée (autre registre) |
| 5 | `ghcr.io/tunsay/ssf-api:latest` (n'existe pas : 404) | refusée (pas de digest) |

## AVANT — `make admission-proof` (04/10, sans Kyverno)

```
== image signée par la CI, par digest — celle qui tourne
   ghcr.io/tunsay/ssf-api:f159b944b9f7b2b4e2ffb87c2fe6b097fdc1a24a@sha256:a0269bc4f1a0674940d19a8ecd6b189e41680fbda4820383d66b62dfed8f6ef7
ADMISE   (après Kyverno : ADMISE)

== image jamais signée, par tag
   ghcr.io/tunsay/ssf-api:8a5d1dc21ae57640f61dd66d470ad5a37470d208
ADMISE   (après Kyverno : REFUSÉE)

== image jamais signée, par digest
   ghcr.io/tunsay/ssf-api@sha256:95dc3cb01a95f49d0515385d9a11cbffd5e38be22385e7de6b9ac345a106a038
ADMISE   (après Kyverno : REFUSÉE)

== image d'un autre registre (Docker Hub), par digest
   docker.io/library/busybox:1.37@sha256:bdf57e528e45e4433820e045b29b4597825a1c9e38353532d90a01445013f82e
ADMISE   (après Kyverno : REFUSÉE)

== tag latest de notre registre
   ghcr.io/tunsay/ssf-api:latest
ADMISE   (après Kyverno : REFUSÉE)
```

Lecture : le cluster contrôle la **forme** d'un pod (PSS : non-root, capacités, seccomp), jamais
**l'image** qu'il fait tourner. Une image jamais signée, une image de n'importe quel registre,
et même une image qui n'existe pas (`latest`, absente de GHCR) passent l'admission : seul le
kubelet échouerait plus tard, au téléchargement. Tout le travail de signature du jalon 4 n'est
aujourd'hui vérifié par **personne** au moment où ça compte : l'entrée dans le cluster.

Accroc au passage : la première tentative a affiché « cluster absent » alors que le cluster
tournait. Un `*` parasite collé devant `docker` faisait échouer la commande, et la commande
proposée confondait « échec de la commande » et « cluster absent » (`a && b || echo ...`).
Remplacée par deux commandes distinctes.

## 5a, étape 1 — la CI signe dans les deux formats (ADR 0012)

- **Vérifié dans le source de cosign v3.1.3 avant d'écrire** (`signcommon/common.go`, l. 444) :
  avec `--use-signing-config` (activé par défaut), cosign **refuse** l'ancien format —
  « must provide --new-bundle-format or --bundle where applicable with --signing-config or
  --use-signing-config ». La signature en ancien format exige donc `--use-signing-config=false`.
  Sans cette lecture, la CI aurait échoué au premier essai.
- `cosign verify` et `verify-attestation` acceptent aussi `--new-bundle-format=false` (option
  dépréciée, comme pour la signature).
- Job `images` : signature et attestation en format v3 (inchangé), **puis** en ancien format ;
  vérification des **deux** formats, avec la même identité exacte.
- **Commit `ddbf88f`**, CI verte. Vérifié dans le registre (sans authentification), pour les deux
  images : l'index v3 (`sha256-<digest>`), la signature ancien format (`.sig`) et l'attestation
  ancien format (`.att`) répondent tous **HTTP 200**. Images : api `sha256:49e6c08a…`, web
  `sha256:69c197b5…`.

## 5a, étape 2 — Kyverno et les politiques, par Terraform

| Fichier | Contenu |
|---|---|
| `platform/kyverno.tf` | Kyverno 1.19.1 (chart 3.9.1) dans `security`, une réplique par contrôleur ; puis les politiques, chart local `k8s/policies` |
| `k8s/policies/templates/verify-signatures.yaml` | `ImageValidatingPolicy` : toute image `ghcr.io/tunsay/ssf-*` du namespace `ssf` doit porter une signature **et** un SBOM CycloneDX signés par l'identité exacte du workflow `ci` sur `main` |
| `k8s/policies/templates/images-ghcr-digest.yaml` | `ValidatingPolicy` : dans `ssf`, seulement `ghcr.io/tunsay/`, et seulement par digest (conteneurs et conteneurs d'initialisation) |
| `platform/app.tf` | l'application est déployée **après** les politiques : ses pods passent eux-mêmes la vérification |
| `platform/variables.tf`, `dev.tfvars` | `admission_action` : **`Warn`** d'abord, puis `Deny` ; images de `ddbf88f` |

Choix notables :
- **`failurePolicy: Fail`** : si Kyverno ne peut pas vérifier, l'image est refusée (même principe
  que J4-I2 : « pas pu contrôler » vaut « refusé »).
- **`mutateDigest: false`** : Kyverno ne réécrit pas les images ; le manifeste déployé reste celui
  du dépôt (sinon ArgoCD, au 5b, verrait une dérive permanente).
- **Deux politiques complémentaires** : la vérification de signature ne regarde que nos images ;
  sans la règle de registre, une image d'un autre registre échapperait à tout contrôle.
- **Phase `Warn` d'abord** : le cluster admet mais renvoie ce qu'il aurait refusé. On vérifie que
  nos propres images passent **avant** de bloquer — l'inverse ferait tomber l'application au
  prochain redémarrage de pod.

**V7 — un champ mal placé évité** : le résumé de la documentation plaçait `failurePolicy` sous
`webhookConfiguration`. Dans la CRD v1 de la 1.19.1, il est directement sous `spec`
(`webhookConfiguration` ne contient que `timeoutSeconds`). Placé selon la CRD.

### Validation et application (04/10)

- `make infra-lint` vert (chart des politiques compris), plan `2 to add, 1 to change,
  0 to destroy` : Kyverno, les politiques en `Warn`, l'application sur les images de `ddbf88f`.
- `make infra-up` : `2 added, 1 changed` ; les 4 contrôleurs Kyverno `Running` en 2 min 32 s,
  sans aucune exception PSS dans `security`.

### Phase `Warn` — `make admission-proof`

```
== image signée par la CI, par digest — celle qui tourne
   ghcr.io/tunsay/ssf-api:ddbf88f56ea55b4ac122314c07f420d6c65f95ae@sha256:49e6c08a…
ADMISE   (après Kyverno : ADMISE)

== image jamais signée, par tag
ADMISE   AVERTISSEMENT : Warning: Policy ssf-signature-ci failed: image ghcr.io/tunsay/ssf-api:8a5d1dc… does not have a digest
         Warning: Policy ssf-registre-et-digest failed: image sans digest — un tag peut être déplacé dans le registre

== image jamais signée, par digest
ADMISE   AVERTISSEMENT : Warning: Policy ssf-signature-ci failed: image non signée par le workflow ci de ce dépôt sur main

== image d'un autre registre (Docker Hub), par digest
ADMISE   AVERTISSEMENT : Warning: Policy ssf-registre-et-digest failed: registre non autorisé — seules les images ghcr.io/tunsay/ sont admises

== tag latest de notre registre
ADMISE   AVERTISSEMENT : Warning: Policy ssf-signature-ci failed: image ghcr.io/tunsay/ssf-api:latest does not have a digest
         Warning: Policy ssf-registre-et-digest failed: image sans digest — un tag peut être déplacé dans le registre
```
(sortie condensée)

- **Le point décisif** : notre image doublement signée passe **sans avertissement** — Kyverno
  vérifie sa signature et son SBOM. On peut bloquer sans faire tomber l'application.
- Chaque autre image est signalée par la bonne règle, avec le bon motif.
- `make app-proof` vert : l'application tourne sur les images doublement signées.

### Mesurer la prémisse de l'ADR 0012

La double signature a été décidée parce que « Kyverno ne lit pas le format v3 sur GHCR » — mais
c'était, jusqu'ici, la description d'une PR, pas une mesure. Sixième test ajouté à la preuve :
l'image de `f159b94`, signée par la CI **au seul format v3** (avant la double signature). Refusée,
elle prouve la prémisse sur notre cluster ; admise un jour, elle remplira la condition de sortie.

## APRÈS 5a — politiques en `Deny` (04/10)

`make infra-up` : `0 added, 1 changed` (politiques `Warn` → `Deny`). Puis `make admission-proof` :

```
== image signée par la CI, par digest — celle qui tourne
   ghcr.io/tunsay/ssf-api:ddbf88f56ea55b4ac122314c07f420d6c65f95ae@sha256:49e6c08aa84ef1596346cf742a6aa0a97108ee05a083fcc2819668729f2e0ee8
ADMISE   (après Kyverno : ADMISE)

== image jamais signée, par tag
   ghcr.io/tunsay/ssf-api:8a5d1dc21ae57640f61dd66d470ad5a37470d208
REFUSÉE  Error from server: error when creating "STDIN": admission webhook "vpol.validate.kyverno.svc-fail" denied the request: Policy ssf-registre-et-digest failed: image sans digest — un tag peut être déplacé dans le registre

== image jamais signée, par digest
   ghcr.io/tunsay/ssf-api@sha256:95dc3cb01a95f49d0515385d9a11cbffd5e38be22385e7de6b9ac345a106a038
REFUSÉE  Error from server: error when creating "STDIN": admission webhook "ivpol.validate.kyverno.svc-fail-finegrained-ssf-signature-ci" denied the request: Policy ssf-signature-ci failed: image non signée par le workflow ci de ce dépôt sur main

== image d'un autre registre (Docker Hub), par digest
   docker.io/library/busybox:1.37@sha256:bdf57e528e45e4433820e045b29b4597825a1c9e38353532d90a01445013f82e
REFUSÉE  Error from server: error when creating "STDIN": admission webhook "vpol.validate.kyverno.svc-fail" denied the request: Policy ssf-registre-et-digest failed: registre non autorisé — seules les images ghcr.io/tunsay/ sont admises

== tag latest de notre registre
   ghcr.io/tunsay/ssf-api:latest
REFUSÉE  Error from server: error when creating "STDIN": admission webhook "ivpol.validate.kyverno.svc-fail-finegrained-ssf-signature-ci" denied the request: Policy ssf-signature-ci failed: image ghcr.io/tunsay/ssf-api:latest does not have a digest

== image signée par la CI, au seul format cosign v3
   ghcr.io/tunsay/ssf-api:f159b944b9f7b2b4e2ffb87c2fe6b097fdc1a24a@sha256:a0269bc4f1a0674940d19a8ecd6b189e41680fbda4820383d66b62dfed8f6ef7
ADMISE   (après Kyverno : ADMISE)
```

| | Avant | Après |
|---|---|---|
| Image signée par la CI, par digest | admise | **admise** |
| Image jamais signée (tag ou digest) | admise | **refusée** — « non signée par le workflow ci de ce dépôt sur main » / « sans digest » |
| Image d'un autre registre | admise | **refusée** — « registre non autorisé » |
| Tag `latest` (inexistant) | admise | **refusée** — « sans digest » |
| Image au seul format v3 | *(test ajouté ensuite)* | **admise** (J5-I1) |

Deux politiques, deux webhooks : `vpol…` (`ValidatingPolicy`, registre et digest) et
`ivpol…` (`ImageValidatingPolicy`, signature). Le suffixe `-fail` est le `failurePolicy: Fail` :
si Kyverno ne répond pas, l'API refuse le pod.

**Nos propres pods sous la politique bloquante** : les trois pods de l'application supprimés,
recréés par Kubernetes **en passant par Kyverno en `Deny`** — aucun événement `FailedCreate` ni
`denied` (« aucun refus d'admission pour l'application »), les trois prêts
(`kubectl wait --for=condition=Ready`), `make app-proof` vert. La preuve ne repose pas que sur le
dry-run : l'application elle-même est admise.

## 5a, dernière preuve — l'image signée au seul format v3, déployée sous `Deny` (04/10)

- **Commit `d9fa77c`** (5a en `Deny`, signature v3 seule) : `ci` et `e2e` verts. Le workflow e2e
  a monté un cluster neuf avec Kyverno en `Deny` **dès le départ**, et l'application y a été
  admise : la preuve ne dépend plus de mon poste.
- Registre, sans authentification : `ssf-api` de d9fa77c (`sha256:752c1b9c…`) → index v3
  `sha256-<digest>` **200**, `.sig` **404**, `.att` **404** : signée au seul format v3.
  `ssf-web` (`sha256:69c197b5…`) a **le même digest qu'en ddbf88f** : le build du front est
  reproductible (mêmes sources, même image à l'octet près), celui de l'API ne l'est pas — noté.
- `make infra-up` (`0 added, 1 changed` : l'application seule), puis :
  - `make admission-proof` : test 1 — l'image API de d9fa77c, v3 seule, celle qui tourne —
    **ADMISE** ; tests 2 à 5 **REFUSÉE** ; test 6 **ADMISE**. Détail : le test 5 (`latest`) est
    cette fois refusé par `ssf-registre-et-digest` et non par `ssf-signature-ci`. Les deux
    politiques le refusent ; l'API renvoie le premier refus reçu, l'ordre n'est pas garanti.
  - `make supply-chain-proof` : OUI partout ; API : signature valide, identité vérifiée, SBOM
    de 2 812 composants.
  - `make app-proof` vert.
- **L'ADR 0013 est prouvé sur un pod réel**, plus seulement en dry-run.

## 5b — décisions de Tunsay (04/10)

| Question | Décision | Raison |
|---|---|---|
| Où ArgoCD lit-il l'état voulu ? (le plan prévoyait un dépôt de manifests séparé) | **Ce dépôt**, `k8s/chart` + `values-dev.yaml` — écart au plan, ADR 0014 | le workflow e2e fait déployer exactement le commit testé ; aucun jeton d'écriture vers un autre dépôt, la CI reste en lecture seule et ne peut pas déployer |
| Kyverno doit-il aussi exiger runAsNonRoot et des limites ? (prévu au plan) | **Non : laissé à PSS restricted + LimitRange** (jalon 2) — écart au plan | PSS refuse déjà le root ; le LimitRange injecte des limites **avant** que Kyverno voie le pod (mutation avant validation), une règle « limites » ne pourrait donc jamais échouer dans `ssf` : un doublon impossible à prouver |
| Bonus reportés du jalon 3 : Sealed Secrets, kube-bench | **Abandonnés** | l'application n'a aucun secret à protéger (zéro secret statique, OIDC partout) ; kube-bench s'exécute en pod privilégié (hostPID, montages du nœud), à l'opposé de la posture du cluster |

## 5b — vérifications faites avant d'écrire (04/10)

| # | Constat | Conséquence |
|---|---|---|
| V8 | Argo CD **v3.5.3** (14/09) est la dernière stable, la 3.6 en pré-version. Charts `argo-cd` 10.9.1 à 10.9.6 : tous en v3.5.3. **10.9.2** (17/09) est la plus récente de plus de 7 jours ; les suivantes ne touchent que redis_exporter, dex et un nom de secret Redis, rien que nous utilisons. | Chart 10.9.2 épinglé. |
| V9 | Chart par défaut, `clusterrole.yaml` du contrôleur : `apiGroups: '*'`, `resources: '*'`, `verbs: '*'`, plus `nonResourceURLs: '*'`. **L'outil de déploiement serait administrateur du cluster.** | `createClusterRoles: false` ; droits donnés par Terraform, dans `ssf` seulement. |
| V10 | Source v3.5.3, `Cluster.RawRestConfig` : pour `https://kubernetes.default.svc` sans identifiants, ArgoCD utilise `rest.InClusterConfig()`, le compte de service de son pod. | Cluster déclaré restreint à `ssf`, **sans aucun jeton stocké**. |
| V11 | Source v3.5.3, `health_ingress.go` : un Ingress est sain **seulement** si `status.loadBalancer.ingress` est rempli, sinon « Progressing ». Traefik en NodePort ne remplit pas ce statut. | Sans correction, l'application resterait « Progressing » pour toujours. Traefik publie `127.0.0.1` (`ingressEndpoint.ip`, présent dans le schéma du chart 41.6.0 ; son Role namespacé a `ingresses/status`). |
| V12 | Chart 10.9.2 : contrôleur, repo-server (et son conteneur d'initialisation), serveur, Redis (UID 999), job d'initialisation de Redis : tous conformes à PSS restricted par défaut. | Namespace `argocd` en restricted, sans exception. |
| V13 | `resource.respectRBAC: "normal"` documenté dans `argocd-cm.yaml` v3.5.3 : ArgoCD ne surveille que ce qu'il a le droit de lister. | Indispensable avec des droits restreints : sinon chaque type interdit (Secrets…) fait échouer la lecture de `ssf`. |

## AVANT 5b — `make drift-proof` (04/10, application gérée par Terraform)

```
== Application gérée par Terraform (helm_release, appliqué à la main)

== État de départ
   APP_ENV de l'API = 'dev' ; variable DRIFT = '' ; front : 2 répliques
   service api : présent ; ConfigMap intrus : absente

== Dérives manuelles
   1. APP_ENV de l'API passé de dev à prod                (décrit dans le dépôt)
   4. variable DRIFT ajoutée à l'API                       (non décrite)
   2. front réduit à 0 réplique                            (décrit dans le dépôt)
   3. service de l'API supprimé                            (décrit dans le dépôt)
   5. ConfigMap « intrus » créée dans le namespace         (non décrite)

== Observation pendant 60 s
PERSISTANTE  après 60 s — 1. APP_ENV de l'API modifié
PERSISTANTE  après 60 s — 2. front à 0 réplique
PERSISTANTE  après 60 s — 3. service de l'API supprimé
PERSISTANTE  après 60 s — 4. variable DRIFT ajoutée
PERSISTANTE  après 60 s — 5. ConfigMap intrus

== État final
   APP_ENV de l'API = 'prod' ; variable DRIFT = 'manuel' ; front : 0 répliques
   service api : absent ; ConfigMap intrus : présente
   (nettoyé : variable DRIFT et ConfigMap intrus)
```

Puis `terraform plan` de la couche platform, juste après :

```
Terraform has compared your real infrastructure against your configuration
and found no differences, so no changes are needed.
code de sortie du plan : 0
```

Lecture : rien ne revient seul, et **Terraform ne voit rien** — il compare l'état de sa release
Helm, pas les objets réels. L'application est en panne (front à zéro, API injoignable),
configurée autrement que le dépôt (`APP_ENV=prod`), et le seul outil de déploiement affirme que
tout est conforme. Seul un humain qui regarde s'en apercevrait.

## APRÈS 5b — `make drift-check` en CI (04/10, commit `1422aae`, cluster neuf)

Bascule locale d'abord : `make infra-up` → `10 added, 1 changed, 1 destroyed` (le seul
`destroy` : `helm_release.app` ; le seul `change` : Traefik qui publie `127.0.0.1`), puis
`ArgoCD, application ssf : OutOfSync/Healthy → Synced/Progressing → Synced/Healthy`, pods prêts,
`make app-proof` vert, `make admission-proof` inchangé (tests 1 et 6 admis, 2 à 5 refusés).

La preuve de référence est celle du workflow e2e, sur un cluster construit de zéro où ArgoCD
déploie le commit testé :

```
== Application gérée par ArgoCD (synchronisation automatique depuis le dépôt)

== État de départ
   APP_ENV de l'API = 'dev' ; variable DRIFT = '' ; front : 2 répliques
   service api : présent ; ConfigMap intrus : absente

== Dérives manuelles
   1. APP_ENV de l'API passé de dev à prod                (décrit dans le dépôt)
   4. variable DRIFT ajoutée à l'API                       (non décrite)
   2. front réduit à 0 réplique                            (décrit dans le dépôt)
   3. service de l'API supprimé                            (décrit dans le dépôt)
   5. ConfigMap « intrus » créée dans le namespace         (non décrite)

== Observation pendant 60 s
ANNULÉE      après ~21 s — 1. APP_ENV de l'API modifié
ANNULÉE      après ~9 s — 2. front à 0 réplique
ANNULÉE      après ~27 s — 3. service de l'API supprimé
PERSISTANTE  après 60 s — 4. variable DRIFT ajoutée
PERSISTANTE  après 60 s — 5. ConfigMap intrus

== État final
   APP_ENV de l'API = 'dev' ; variable DRIFT = 'manuel' ; front : 2 répliques
   service api : présent ; ConfigMap intrus : présente
   (nettoyé : variable DRIFT et ConfigMap intrus)

== Ce que le contrôleur d'ArgoCD a le droit de faire
   modifier les Deployments de ssf                      : yes
   lire les Secrets de ssf                              : no
   supprimer les NetworkPolicies de ssf                 : no
   se donner des droits dans ssf (RoleBinding)          : no
   créer un Deployment dans kube-system                : no
   se donner des droits sur le cluster                  : no

DÉRIVE CONFORME : dérives décrites annulées, droits d'ArgoCD bornés à ssf
```

| Modification manuelle | Avant (Terraform) | Après (ArgoCD) |
|---|---|---|
| 1. `APP_ENV` passé de `dev` à `prod` | persistante | **annulée en ~21 s** |
| 2. front à 0 réplique (application en panne) | persistante | **annulée en ~9 s** |
| 3. Service de l'API supprimé (API injoignable) | persistante | **annulée en ~27 s** |
| 4. variable ajoutée, que le dépôt ne décrit pas | persistante | persistante |
| 5. objet étranger créé dans `ssf` | persistante | persistante |
| L'outil de déploiement voit-il la dérive ? | **non** (`terraform plan` : no differences) | **oui**, et la répare |

Lecture :
- **Ce que le dépôt décrit revient seul**, en moins de 30 s, sans intervention.
- **Ce qu'il ne décrit pas reste** — limite réelle, mesurée. ArgoCD compare avec ce qu'il a
  lui-même appliqué : un champ qu'il n'a jamais posé n'est pas, pour lui, une dérive. Et un objet
  qu'il n'a pas créé ne le concerne pas : ses droits ne lui permettent même pas de lire les
  ConfigMaps de `ssf`. Ce cas relève des autres verrous : qui peut écrire dans `ssf` (droits
  Kubernetes), et ce qui peut y tourner (Kyverno).
- **Ses droits sont bornés** : écrire des Deployments dans `ssf`, oui ; lire un secret, toucher
  au réseau, se donner des droits, sortir de `ssf`, non.
- Sur le poste, la même preuve a donné une réparation en ~90 s au lieu de quelques secondes :
  incident J5-I3.

## Incidents

### J5-I1 — La prémisse de l'ADR 0012 était fausse : la mesure la dément

- **Symptôme** : sixième test, en phase `Warn` :
  ```
  == image signée par la CI, au seul format cosign v3 (ADR 0012)
     ghcr.io/tunsay/ssf-api:f159b944…@sha256:a0269bc4…
  ADMISE   (après Kyverno : REFUSÉE tant que Kyverno ne lit pas ce format sur GHCR)
  ```
  Admise **sans avertissement** : Kyverno 1.19.1 a vérifié sa signature et son SBOM.
- **Explication écartée d'abord** : cette image porterait aussi une signature à l'ancien format.
  Vérifié dans le registre : index v3 `sha256-a0269bc4…` → 200, `.sig` → **404**, `.att` →
  **404**. Seul le format v3 existe : c'est bien lui que Kyverno a vérifié.
- **Cause de l'erreur** : la PR kyverno#16754, sur laquelle reposait la décision, ne modifie qu'un
  fichier : `pkg/image/verifiers/cpol/cosign/sigstore.go`. `cpol` = **ClusterPolicy**, l'ancien
  type de politique. Le défaut GHCR est réel, mais dans ce chemin de code ; nous utilisons
  `ImageValidatingPolicy` — choisi justement parce que ClusterPolicy est dépréciée — qui a son
  propre chemin. Les tickets #17363 (clé ou KMS, pas sans clé) et #16678 ne concernent pas non
  plus notre configuration (sans clé, attestation `intoto`).
- **Ce que la mesure a évité** : maintenir une double signature dans la CI, avec une option
  dépréciée de cosign, pour un défaut qui ne nous touche pas.
- **Ce que la mesure ne prouve pas encore** : que la validation du **SBOM** discrimine. Aucune
  image « signée mais sans SBOM » n'est disponible pour le vérifier : la règle passe pour les
  images qui ont un SBOM, mais n'a pas été vue refuser une image qui n'en a pas. Limite notée.
- **Leçon** : lire une PR, c'est lire **ce qu'elle modifie**, pas seulement ce qu'elle décrit.
  Et la décision a été rattrapée parce que le test de sa prémisse a été écrit avant d'en avoir
  besoin.
- **Décision de Tunsay : retirer la double signature** (ADR 0013, qui remplace ce volet de
  l'ADR 0012 ; l'ADR 0012 n'est pas modifié). La CI ne signe plus qu'au format v3 ; le test 6
  devient « attendu admis ». Dans la même passe, les politiques passent en **`Deny`**.

### J5-I2 — « Application en panne » : la vérification se trompait, pas Kyverno

- **Symptôme** : après suppression des pods de l'application (pour les faire recréer sous la
  politique bloquante), `kubectl rollout status` répond aussitôt « successfully rolled out »,
  puis `make app-proof` : `No resources found in ssf namespace` et **503** sur l'application.
- **Fausse piste immédiate** : Kyverno refuserait nos propres pods. Diagnostic en lecture seule
  (`get deploy,rs,pods` + événements) : les trois pods sont `Running`, événements
  `SuccessfulCreate`, `Scheduled`, `Pulled`, `Started`, aucun `FailedCreate` ni `denied`.
- **Cause** : la vérification proposée était fausse. `rollout status` ne regarde que le
  déploiement d'une **nouvelle version** ; le Deployment n'ayant pas changé, il répond « terminé »
  sans attendre la recréation des pods. `app-proof` a tourné dans l'intervalle, avant que les
  nouveaux pods n'existent.
- **Correction** : attendre les pods eux-mêmes, `kubectl wait --for=condition=Ready pod -l
  app.kubernetes.io/name=ssf`. Choix conservé : recréer les pods par suppression plutôt que par
  `kubectl rollout restart`, qui modifierait le Deployment géré par Terraform.
- **Leçon** : une commande d'attente doit attendre l'état qu'on veut constater, pas un état
  voisin. Une vérification qui répond trop vite est plus trompeuse qu'une absence de
  vérification.

### J5-I3 — En local, ArgoCD répare en ~90 s au lieu de quelques secondes : Kyverno vérifie aussi les Deployments

- **Symptôme** : `make drift-proof` après la bascule vers ArgoCD, sur le poste : les cinq dérives
  `PERSISTANTE après 60 s`, l'application injoignable sur 8081. Puis le nettoyage du script
  (`kubectl set env deploy/api DRIFT-`) échoue : `Timeout: request did not complete within
  requested timeout - context deadline exceeded`. Quelques minutes plus tard, l'application
  fonctionne de nouveau.
- **Diagnostic, en lecture seule** (21:22 CEST, soit 19:22Z) :
  - application `Synced/Healthy`, dernière opération `Succeeded — successfully synced (all tasks
    run)` ; Service `api` recréé à 19:15:00Z (âge 7 min 27 s) ;
  - journal du contrôleur ArgoCD : `Skipping auto-sync: another operation is in progress`
    (19:14:47Z), puis `already attempted sync to [1422aae…] … retrying in 961ms` (19:14:59Z), puis
    une nouvelle opération d'auto-réparation sur le Service `api` et le Deployment `web`,
    `SelfHealAttemptsCount: 2` (19:15:00Z), et `application status is Synced` dès 19:15:15Z ;
  - journal de Kyverno : le webhook `ivpol/validate/ssf-signature-ci` reçoit des **mises à jour
    du Deployment `api`** — d'ArgoCD à 19:14:29Z (`?timeout=10s`), puis du nettoyage à 19:15:37Z
    (`?timeout=6s`) — et répond après l'abandon de l'API Kubernetes : `write: broken pipe` ;
  - nœuds : control-plane 18,6 % CPU et 1,46 Go / 7,45 Go, workers sous 5 % CPU : **pas de
    saturation**.
- **Cause** : la politique de signature, écrite pour les pods, est **aussi appliquée aux
  Deployments** — Kyverno génère les règles équivalentes pour les contrôleurs de pods, ce que son
  journal montre. Chaque modification d'un Deployment déclenche donc une vérification de
  signature (GHCR, Rekor) **dans** la requête d'admission. Sur le poste, elle a dépassé le temps
  accordé au webhook ; avec `failurePolicy: Fail`, la mise à jour est refusée. La première
  réparation d'ArgoCD a échoué sur le Deployment `api`, la nouvelle tentative a réussi :
  application rétablie **environ 90 s** après la dérive, au-delà de la fenêtre de 60 s.
- **En CI, sur le cluster neuf** : `make drift-check` passe — dérives décrites annulées en moins
  de 60 s, workflow e2e vert. Même politique, même Kyverno ; la vérification y est plus rapide.
  La cause exacte de la lenteur locale (réseau du poste vers GHCR et Rekor, cache de Kyverno)
  n'est **pas mesurée**.
- **Correction** : aucune à ce stade, choix documenté. Restreindre la politique aux pods
  sortirait Kyverno du chemin des Deployments (les pods restent vérifiés à leur création), au
  prix d'un refus plus tardif d'un Deployment non signé. Point ouvert.
- **Leçon** : une politique d'admission est sur le chemin critique de **tout** ce qui la
  traverse, y compris de l'outil qui répare. Avec `failurePolicy: Fail`, une lenteur devient un
  refus. Et deux résultats différents, CI et poste, sont tous les deux vrais : on documente les
  deux.
