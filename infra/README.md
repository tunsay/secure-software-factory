# infra/ — Terraform

Deux couches, comme sur un cloud : un bootstrap qui crée le cluster, puis une plateforme qui le
configure. Pas de fournisseur cloud : Terraform pilote un cluster kind local
([ADR 0004](../docs/adr/0004-terraform-sans-fournisseur-cloud.md)).

```
terraform/
  cluster/       crée le cluster kind (1 control-plane, 2 workers), image de nœud épinglée par digest
  platform/
    main.tf      namespaces ssf (application), ingress, security
    ingress.tf   Traefik : NodePort, droits limités aux namespaces servis
    network.tf   NetworkPolicies : tout fermé, puis Traefik → web → api et DNS
    kyverno.tf   Kyverno et les politiques d'admission de ssf (jalon 5a)
    argocd.tf    ArgoCD, sans droits de cluster, et l'Application qui déploie k8s/chart (jalon 5b)
  modules/
    namespace/   namespace durci : Pod Security Standards restricted, quota, limites, compte
                 « default » sans jeton
```

## Où vivent les états Terraform

| Couche | État | Pourquoi |
|---|---|---|
| `cluster` | **`~/.local/state/ssf/cluster.tfstate`**, dans le dossier personnel WSL (droits 700), **hors du dépôt** | il contient la clé privée administrateur du cluster, en clair (provider `tehcyx/kind`) — incident J4-I6 |
| `platform` | Secret du cluster, namespace `terraform-state`, verrou par lease | état distant ; sa durée de vie est celle du cluster |

Le kubeconfig est lui aussi hors du dépôt : `~/.kube/ssf-dev`.

## Commandes

```bash
make infra-up      # cluster puis platform ; chaque apply affiche son plan et attend « yes »,
                   # puis attend qu'ArgoCD ait déployé l'application (make app-wait)
make infra-plan    # plan de la couche platform, sans appliquer
make infra-lint    # chart-lint, fmt, validate, Checkov, trivy config — ce que la CI exécute
make infra-down    # destroy platform puis cluster
```

La CI e2e appelle le même `make infra-up`, avec `TF_APPLY_FLAGS=-auto-approve`, sur un cluster
éphémère, et fait déployer par ArgoCD le commit testé (`TF_PLATFORM_VARS=-var=argocd_revision=<sha>`).

Terraform ne déploie plus l'application (jalon 5b) : la version déployée est dans
`k8s/chart/values-dev.yaml`, appliquée par ArgoCD après chaque commit poussé sur main.

## Règles

- Aucun secret dans le code. États et kubeconfig contenant des identifiants : hors du dépôt.
- Versions de providers épinglées, `.terraform.lock.hcl` commité.
- Tout changement passe par `plan` avant `apply`. Jamais de `kubectl apply` à la main sur ce que
  Terraform ou ArgoCD gère (ArgoCD annule de toute façon ce qui touche l'application).
- Ne jamais copier ni capturer le plan d'un **remplacement** du cluster : il affiche la clé
  privée en clair (incident I2 du jalon 3).

Décisions liées : [ADR 0007](../docs/adr/0007-ingress-traefik-nodeport.md) (Traefik, NodePort),
[ADR 0008](../docs/adr/0008-cloisonnement-reseau-et-droits.md) (cloisonnement),
[ADR 0009](../docs/adr/0009-preuve-reseau-en-ci-ephemere.md) (preuve réseau en CI).
