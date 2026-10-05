# Rapport de projet

Un chapitre par jalon, rédigé à la fin de chaque jalon, versionné avec le code.

| Document | Contenu |
|---|---|
| [plan](plan.md) | Plan directeur des six jalons — vue d'ensemble et détail de chacun |
| [00-contexte](00-contexte.md) | Analyse de 10 offres, choix de la stack, contraintes |
| [01-jalon-1](01-jalon-1.md) | Socle applicatif, chaîne de contrôle, incidents, tests d'intrusion |
| [02-jalon-2](02-jalon-2.md) | Terraform pilote le cluster kind, namespaces PSS, backend distant, GHCR, job IaC — six incidents |
| [03-jalon-3](03-jalon-3.md) | L'app dans le cluster derrière Traefik, cloisonnement réseau et identité, preuve sur cluster éphémère en CI — dix incidents. [Journal de bord](journal-jalon-3.md) |
| [04-jalon-4](04-jalon-4.md) | Chaîne d'approvisionnement : images signées sans clé, SBOM attesté, déploiement par digest, build figé, moindre privilège en CI — sept incidents. [Journal de bord](journal-jalon-4.md) |
| [05-jalon-5](05-jalon-5.md) | Policy as code et GitOps : Kyverno n'admet que les images signées par la CI, ArgoCD déploie depuis le dépôt sans droits de cluster et annule les modifications manuelles — trois incidents. [Journal de bord](journal-jalon-5.md) |
| [06-jalon-6](06-jalon-6.md) | DAST bloquant, observabilité de la posture de sécurité (Prometheus, Grafana, trivy-operator aux droits restreints), modèle de menaces, vitrine — deux incidents. [Journal de bord](journal-jalon-6.md) |
| [07-conclusion](07-conclusion.md) | Comment les six jalons s'emboîtent, et le tableau de synthèse : de quoi on est protégé, par quelle technologie, depuis quel jalon, prouvé par quelle commande |

Le PDF complet s'assemble à partir de ces fichiers et du [modèle de menaces](../threat-model.md) : `make report-pdf`.
Les captures d'écran vont dans [`img/`](img/README.md).
