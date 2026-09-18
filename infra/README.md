# infra/ — Terraform

Deux couches, comme sur un cloud : un bootstrap en état local, puis une plateforme en état distant.

```
terraform/
  cluster/     crée le cluster kind — état local (bootstrap)
  platform/    configure le cluster — état distant (backend kubernetes, verrou par lease)
  modules/
    namespace/ namespace durci : Pod Security Standards restricted, quota, limites
```

## Commandes

```bash
make infra-up      # cluster puis platform, apply enchaînés
make infra-plan    # plan de la couche platform
make infra-lint    # fmt, validate, checkov, trivy config — ce que la CI exécute
make infra-down    # destroy platform puis cluster
```

## Règles

- Aucun secret dans le code. Le kubeconfig est écrit hors du dépôt (`~/.kube/ssf-dev`).
- Versions de providers épinglées, `.terraform.lock.hcl` commité.
- Tout changement passe par `plan` avant `apply`. Jamais de `kubectl apply` à la main sur
  ce que Terraform gère.
- Voir [ADR 0004](../docs/adr/0004-terraform-sans-fournisseur-cloud.md) pour le choix
  d'un cluster local plutôt qu'un cloud.
