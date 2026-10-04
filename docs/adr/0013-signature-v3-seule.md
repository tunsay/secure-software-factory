# ADR 0013 — Signature au seul format cosign v3 : la double signature est retirée

**Statut** : accepté · **Date** : 2026-10-04 · **Remplace** le volet « double signature » de
l'ADR 0012 (le reste de l'ADR 0012 — Kyverno, politiques CEL — reste valable)

## Contexte

L'ADR 0012 a introduit une double signature (format cosign v3 + ancien format) parce que
« Kyverno 1.19.1 ne vérifie pas les bundles cosign v3 rangés sur GHCR ». Cette prémisse reposait
sur la **description** de la PR kyverno#16754, pas sur une mesure.

Mesure du 4 octobre (`make admission-proof`, test 6, journal du jalon 5, J5-I1) : une image
signée par la CI **au seul format v3** — aucune signature `.sig` ni attestation `.att` dans le
registre, vérifié — est **admise sans avertissement** par notre `ImageValidatingPolicy`, signature
et SBOM vérifiés.

Explication : la PR kyverno#16754 ne modifie que `pkg/image/verifiers/cpol/cosign/sigstore.go`,
le code de **ClusterPolicy**. Le défaut GHCR est réel dans ce chemin ; nous utilisons
`ImageValidatingPolicy`, qui a le sien et lit correctement le schéma de repli par tag de GHCR.

## Décision

- La CI ne signe et n'atteste plus qu'au **format cosign v3**. Les options dépréciées
  `--new-bundle-format=false` et `--use-signing-config=false` disparaissent de la CI.
- Les images déjà publiées en double format restent valides : leur signature v3 suffit.
- Le test 6 de `make admission-proof` (image v3 seule) passe d'« attendu refusé » à
  « attendu admis » et garde la preuve que le format v3 seul suffit.

## Conséquences

- Plus d'option dépréciée de cosign dans la chaîne ; une seule signature et une seule
  attestation par image dans le journal public Rekor.
- Si une version future de Kyverno régressait sur ce format, la CI ne le verrait pas, mais
  `make admission-proof` (test 1 et test 6, attendus admis) et le workflow e2e (déploiement de
  l'application sous politique bloquante) échoueraient.
- Leçon consignée : une PR se lit par ce qu'elle modifie, pas seulement par ce qu'elle décrit.
