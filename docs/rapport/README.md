# Rapport de projet

Un chapitre par jalon, rédigé à la fin de chaque jalon, versionné avec le code.

| Document | Contenu |
|---|---|
| [plan](plan.md) | Plan directeur des six jalons — vue d'ensemble et détail de chacun |
| [00-contexte](00-contexte.md) | Analyse de 10 offres, choix de la stack, contraintes |
| [01-jalon-1](01-jalon-1.md) | Socle applicatif, chaîne de contrôle, incidents, tests d'intrusion |
| [02-jalon-2](02-jalon-2.md) | Terraform pilote le cluster kind, namespaces PSS, backend distant, GHCR, job IaC — six incidents |
| [03-jalon-3](03-jalon-3.md) | L'app dans le cluster derrière Traefik, cloisonnement réseau et identité, preuve sur cluster éphémère en CI — neuf incidents. [Journal de bord](journal-jalon-3.md) |
| 04-jalon-4 | Pipeline : SBOM, signature, IaC scan — à venir |
| 05-jalon-5 | Policy as code, GitOps — à venir |
| 06-jalon-6 | Observabilité, DAST, modèle de menaces — à venir |

Le PDF final est assemblé à partir de ces fichiers à la fin du jalon 6.
Les captures d'écran vont dans [`img/`](img/README.md).
