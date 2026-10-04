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
