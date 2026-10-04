# ADR 0012 — Admission par Kyverno (politiques CEL), double signature transitoire

**Statut** : accepté · **Date** : 2026-10-04 · **Complète** l'ADR 0010

## Contexte

Mesure du 4 octobre (`make admission-proof`, avant) : le cluster admet une image jamais signée,
une image de n'importe quel registre, et même une image qui n'existe pas. Les signatures du
jalon 4 ne sont vérifiées par personne au moment où ça compte : l'entrée dans le cluster.

Kyverno est l'outil prévu. Deux faits, vérifiés avant d'écrire (journal du jalon 5, V2 à V4) :

- **Kyverno 1.19.1** (dernière version publiée) **ne vérifie pas les signatures cosign v3
  rangées sur GHCR** : GHCR n'a pas l'API OCI referrers, cosign range les bundles dans un tag de
  repli, et Kyverno écarte ces descripteurs (PR kyverno#16754, ouverte ; correctifs liés prévus
  pour la 1.19.2, non publiée). Une règle bloquante refuserait nos propres images.
- **Kyverno 1.19 déprécie `ClusterPolicy`**, retirée en 1.20 (~novembre 2026), au profit de types
  CEL : `ImageValidatingPolicy`, `ValidatingPolicy`.

## Décision

1. **Kyverno 1.19.1**, chart 3.9.1, installé par Terraform dans le namespace `security` (PSS
   restricted : le chart est conforme par défaut).
2. **Politiques écrites dans les types CEL** (`policies.kyverno.io/v1`) et non en `ClusterPolicy` :
   pas de code déprécié qui casse à la prochaine version mineure.
3. **Double signature, transitoire** : la CI signe et atteste dans le format cosign v3 **et** dans
   l'ancien format (`--new-bundle-format=false`, avec `--use-signing-config=false`, exigé par
   cosign pour ce format). Kyverno vérifie l'ancien ; `cosign verify` et la preuve locale
   continuent de vérifier le nouveau. La CI vérifie les deux, avec la même identité exacte.
4. **Condition de sortie** : dès qu'une version **publiée** de Kyverno vérifie les bundles cosign v3
   sur un registre sans API referrers (prouvé sur notre cluster, pas sur parole), retirer l'ancien
   format de la CI et de la politique.

## Alternatives écartées

- **policy-controller (Sigstore) + ValidatingAdmissionPolicy natives** : même famille que cosign,
  donc probablement compatible plus tôt ; mais s'écarte du plan, ajoute un composant pour la
  seule signature, et Kyverno est plus répandu.
- **Attendre Kyverno 1.19.2 et la fusion du correctif** : date inconnue, jalon bloqué.
- **`ClusterPolicy` avec `verifyImages`** : chemin le plus documenté en ligne, mais déprécié et
  retiré dans la version suivante.

## Conséquences

- Chaque image porte deux signatures et deux attestations : deux fois plus d'entrées dans le
  journal public Rekor, et une option de cosign dépréciée (retirée en cosign v4) dans la CI. C'est
  le prix, assumé et borné, de la compatibilité.
- La condition de sortie est vérifiable : `make admission-proof` avec une image signée dans le
  seul format v3 doit être admise.
