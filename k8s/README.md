# k8s/ — chart Helm de l'application, et ce qui le déploie

```
chart/
  Chart.yaml
  values.yaml
  values-dev.yaml       version déployée (tag + digests) : déployer = un commit sur ce fichier
  templates/
    _helpers.tpl          image dépôt:tag@digest (refuse une image sans digest), securityContext
    api.yaml              Deployment + Service de l'API
    web.yaml              Deployment + Service du front (nginx), deux répliques réparties sur les
                          workers quand c'est possible (ScheduleAnyway : pas garanti)
    ingress.yaml          seul point d'entrée, vers web ; l'API n'a aucune route externe
    serviceaccounts.yaml  un compte par composant, sans jeton Kubernetes
policies/               politiques d'admission Kyverno (jalon 5a) : signature, registre, digest
argocd/                 projet et Application ArgoCD (jalon 5b) : ce dépôt, namespace ssf, rien d'autre
```

Depuis le jalon 5b, le chart est déployé par **ArgoCD**, depuis ce dépôt, avec
`values-dev.yaml` ; une modification manuelle du cluster est annulée (selfHeal). ArgoCD n'a
aucun droit de cluster : il n'écrit que dans `ssf`, et seulement les types d'objets du chart
([ADR 0014](../docs/adr/0014-gitops-argocd-sans-droits-cluster.md)).

## Ce que le chart garantit

- **Pod Security Standards restricted** : non-root, UID explicite, aucune capacité, pas
  d'escalade de privilège, seccomp `RuntimeDefault`, système de fichiers en lecture seule.
- **Image par digest obligatoire** : le chart refuse de s'installer sans digest `sha256` valide ;
  le tag (SHA du commit) reste pour la lecture.
- **Aucune identité Kubernetes** dans les pods : comptes dédiés, jeton non monté.
- Pas de HPA : l'API stocke ses données en mémoire, deux répliques donneraient deux états
  différents.

## Ce qui n'est pas ici, et où le trouver

| Élément | Où | Pourquoi |
|---|---|---|
| Cluster kind | `infra/terraform/cluster` | créé par Terraform, pas par un fichier kind |
| NetworkPolicies | `infra/terraform/platform/network.tf` | portées par la plateforme : celui qui déploie l'application ne doit pas pouvoir élargir ses propres flux ([ADR 0008](../docs/adr/0008-cloisonnement-reseau-et-droits.md)) |
| Traefik | `infra/terraform/platform/ingress.tf` | composant de plateforme |
| Kyverno, ArgoCD | `infra/terraform/platform/kyverno.tf`, `argocd.tf` | composants de plateforme ; leurs politiques et leur Application sont ici, dans `policies/` et `argocd/` |

## Vérifier le chart

```bash
make chart-lint   # helm lint --strict des trois charts, rendu avec values-dev.yaml, Trivy sur les manifests
```

Même contrôle en hook pre-commit (dès qu'un fichier du chart change) et en CI.
