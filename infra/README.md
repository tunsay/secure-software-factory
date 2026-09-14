# infra/ — Terraform (semaine 2)

```
bootstrap/      backend d'état : S3 chiffré + versioning + verrou (appliqué une fois, à la main)
terraform/
  modules/      ecr, iam-oidc, network
  envs/dev/     composition + variables
```

Règles :

- Aucune clé d'accès statique. La CI s'authentifie via un rôle IAM fédéré OIDC.
- Aucun NAT Gateway (ADR 0003).
- `*.tfvars` jamais commités ; un `dev.example.tfvars` sert de modèle.
- Alerte budget AWS à 1 € avant le premier `apply`.
