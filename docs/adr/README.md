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
| [0010](0010-signature-sans-cle-et-sbom.md) | Images signées sans clé, SBOM attesté, publication de l'image scannée | accepté |
| [0011](0011-moindre-privilege-des-jobs-ci.md) | CI : chaque job ne reçoit que les droits dont il a besoin | accepté |
| [0012](0012-kyverno-et-double-signature.md) | Admission par Kyverno (politiques CEL), double signature transitoire | accepté ; volet double signature remplacé par 0013 |
| [0013](0013-signature-v3-seule.md) | Signature au seul format cosign v3 : la double signature est retirée | accepté |
| [0014](0014-gitops-argocd-sans-droits-cluster.md) | GitOps : ArgoCD déploie l'application depuis ce dépôt, sans droits sur le cluster | accepté |
