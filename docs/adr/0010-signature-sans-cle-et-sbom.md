# ADR 0010 — Images signées sans clé, SBOM attesté, publication de l'image scannée

**Statut** : accepté · **Date** : 2026-10-03

## Contexte

Mesure du 3 octobre (`make supply-chain-proof`, avant) : aucune image publiée n'est signée,
aucune ne porte de SBOM, le cluster les désigne par tag. Rien ne distingue une image construite
par la CI d'une image poussée par quiconque obtiendrait le droit d'écrire dans le registre.
De plus, l'image publiée était une **seconde construction** (depuis le cache), distincte de
celle que le smoke test et Trivy venaient de contrôler.

## Décision

1. **Publier l'image contrôlée elle-même** : l'image chargée, testée et scannée est poussée
   telle quelle (`docker push`), sans reconstruction. La CI vérifie que la configuration de
   l'image publiée (`config.digest`) est celle de l'image scannée.
2. **SBOM CycloneDX** généré par Syft sur l'image publiée, conservé comme artefact de la CI.
3. **Signature Cosign sans clé** (*keyless*) : le workflow obtient un jeton OIDC de GitHub
   (`id-token: write`), Fulcio délivre un certificat de quelques minutes à cette identité, la
   signature est inscrite au journal de transparence public Rekor. **On signe le digest**,
   jamais le tag.
4. **SBOM attesté** : `cosign attest --type cyclonedx` lie le SBOM à l'image, signé par la même
   identité. Le SBOM voyage avec l'image et ne peut pas être modifié sans invalider l'attestation.
5. **Règle de vérification unique**, appliquée en CI juste après la signature, par
   `make supply-chain-proof`, puis par Kyverno au jalon 5 : identité **exacte**
   `https://github.com/tunsay/secure-software-factory/.github/workflows/ci.yml@refs/heads/main`,
   émetteur `https://token.actions.githubusercontent.com`. Une signature d'un autre workflow,
   d'une autre branche ou d'un fork ne passe pas.
6. **Déploiement par digest** (étape suivante du jalon) : le cluster désigne l'image par
   `tag@digest` ; le tag reste lisible, seul le digest fait foi.

Versions : cosign v3.1.3, syft v1.52.0 (la v1.54.0 avait deux jours : même délai de carence de
7 jours que Dependabot), actions épinglées par SHA.

## Alternatives écartées

- **Cosign avec une paire de clés** stockée dans les secrets GitHub : un secret statique de plus
  à protéger et à faire tourner, contraire à la règle « zéro secret statique » (ADR 0004).
- **Attestations BuildKit** (`provenance`, `sbom` de buildx) : produites dans l'index de l'image
  mais pas signées par une identité vérifiable ; moins directement exploitables par Kyverno.
  Pourront compléter plus tard.
- **Notation (Notary v2)** : intégration moins directe avec l'identité OIDC de GitHub Actions.

## Conséquences

- Chaque signature est **publique** (Rekor) : nom du dépôt, du workflow, digest de l'image.
  Sans enjeu pour un dépôt public ; à reconsidérer pour un projet privé (instance Sigstore
  privée).
- La publication dépend de la disponibilité de Sigstore. S'il est indisponible, le job échoue
  après le `push` : l'image existe dans le registre **sans signature**, donc sera refusée par
  toute vérification. L'échec est sûr, pas silencieux.
- cosign v3 stocke la signature comme artefact OCI 1.1 rattaché à l'image (et non plus comme un
  tag `.sig`). Kyverno, au jalon 5, devra savoir vérifier ce format : à contrôler avant de s'y
  appuyer.
