# Architecture Decision Records

Format court, une décision par fichier, jamais modifié après coup : une décision annulée
est remplacée par un nouvel ADR qui la référence.

| # | Décision | Statut |
|---|---|---|
| [0001](0001-application-volontairement-triviale.md) | L'application est volontairement triviale | accepté |
| [0002](0002-kubernetes-local-terraform-aws.md) | Kubernetes en local (kind), Terraform sur AWS free tier | volet AWS remplacé par 0004 |
| [0003](0003-pas-de-nat-gateway.md) | Pas de NAT Gateway | sans objet depuis 0004 |
| [0004](0004-terraform-sans-fournisseur-cloud.md) | Terraform pilote le cluster local, registre GHCR, sans fournisseur cloud | accepté |
| 0005 | Python/FastAPI plutôt que Go pour le back | à rédiger |
| 0006 | GitHub Actions en référence, GitLab CI maintenu en miroir | à rédiger |
| [0007](0007-ingress-traefik-nodeport.md) | Ingress : Traefik exposé par NodePort, sans exception PSS | accepté |
| [0008](0008-cloisonnement-reseau-et-droits.md) | Cloisonnement : NetworkPolicies et droits portés par la plateforme | accepté |
| [0009](0009-preuve-reseau-en-ci-ephemere.md) | Cloisonnement réseau prouvé sur cluster éphémère en CI, kindnet conservé | accepté |
