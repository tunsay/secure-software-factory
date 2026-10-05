# Secure Software Factory

> Une application volontairement triviale, entourée d'une chaîne de build, de déploiement et de
> contrôle sécurisée de bout en bout. **Le produit livré n'est pas l'application — c'est la
> chaîne.**

Projet portfolio DevSecOps : Terraform, Kubernetes (kind), GitHub Actions et GitLab CI, signature
Cosign sans clé, Kyverno, ArgoCD, Prometheus et Grafana, OWASP ZAP, trivy-operator. Chaque
contrôle est **prouvé par une commande** ou un run de CI qui échoue s'il disparaît, et chaque
étape est racontée avec son état **avant / après** et ses incidents.

Code source : [github.com/tunsay/secure-software-factory](https://github.com/tunsay/secure-software-factory)

## Par où commencer

1. [Le modèle de menaces](threat-model.md) — ce qu'on protège, contre qui, par quel contrôle, avec
   quelle preuve, et ce qui reste assumé (STRIDE cadré par EBIOS RM).
2. [Le plan des six jalons](rapport/plan.md) — la progression, et les écarts au plan.
3. Les chapitres, un par jalon :
   - [Contexte et choix de la stack](rapport/00-contexte.md)
   - [Jalon 1 — socle applicatif et chaîne de contrôle](rapport/01-jalon-1.md)
   - [Jalon 2 — Terraform pilote le cluster](rapport/02-jalon-2.md)
   - [Jalon 3 — déploiement et cloisonnement](rapport/03-jalon-3.md)
   - [Jalon 4 — chaîne d'approvisionnement : signature, SBOM, digests](rapport/04-jalon-4.md)
   - [Jalon 5 — policy as code (Kyverno) et GitOps (ArgoCD)](rapport/05-jalon-5.md)
   - [Jalon 6 — DAST, observabilité, modèle de menaces](rapport/06-jalon-6.md)
   - [Conclusion — comment les jalons s'emboîtent, et de quoi on est protégé](rapport/07-conclusion.md)
4. [Les décisions d'architecture](adr/README.md), une par fichier, jamais réécrites.
5. [Lancer le projet sur son PC](INSTALLATION.md), pas à pas, de Windows neuf au cluster complet.

## Ce qui est démontré, en une phrase par jalon

- **Jalon 1** : aucun code, aucune dépendance, aucune image vulnérable ne passe la CI.
- **Jalon 2** : l'infrastructure est du code, contrôlé comme du code ; un pod root est refusé.
- **Jalon 3** : l'application tourne cloisonnée — réseau fermé par défaut, aucun jeton dans les pods.
- **Jalon 4** : ce qui est publié est exactement ce qui a été scanné, signé, inventorié.
- **Jalon 5** : le cluster refuse ce que la CI n'a pas signé, et revient seul à l'état du dépôt.
- **Jalon 6** : l'application est testée de l'extérieur, et la chaîne raconte ce qu'elle refuse,
  répare et trouve.
