# k8s/ — chart Helm de l'application

```
chart/
  Chart.yaml
  values.yaml
  templates/
    _helpers.tpl          image dépôt:tag@digest (refuse une image sans digest), securityContext
    api.yaml              Deployment + Service de l'API
    web.yaml              Deployment + Service du front (nginx), deux répliques réparties sur les
                          workers quand c'est possible (ScheduleAnyway : pas garanti)
    ingress.yaml          seul point d'entrée, vers web ; l'API n'a aucune route externe
    serviceaccounts.yaml  un compte par composant, sans jeton Kubernetes
```

Le chart est installé par Terraform (`infra/terraform/platform/app.tf`), jusqu'à ce qu'ArgoCD
reprenne le déploiement de l'application au jalon 5.

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
| Politiques Kyverno | jalon 5 | vérification de signature à l'admission |

## Vérifier le chart

```bash
make chart-lint   # helm lint --strict, rendu avec la version déployée, Trivy sur les manifests
```

Même contrôle en hook pre-commit (dès qu'un fichier du chart change) et en CI.
