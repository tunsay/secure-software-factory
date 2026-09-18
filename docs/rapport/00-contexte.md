# Chapitre 0 — Contexte et choix de la stack

*14 septembre 2026*

## Pourquoi ce projet

Ce projet est une vitrine DevSecOps. Il n'a pas pour but de livrer une application, mais de
démontrer la maîtrise de ce qui entoure une application en production : infrastructure as code,
orchestration, intégration continue, contrôles de sécurité automatisés, observabilité.

Le principe directeur, formalisé dans l'[ADR 0001](../adr/0001-application-volontairement-triviale.md) :
**l'application est volontairement triviale**. Tout le temps disponible va dans la chaîne.

## Ce que demande le marché

Dix offres DevSecOps en CDI, Île-de-France, relevées sur HelloWork le 14 septembre 2026 :
DEODIS, Metanext, Oreve / Ortec Group, Squad, CND (MINARM), Groupe Créative, BNP Paribas,
Naval Group, Groupe Trèfle, Sopra Steria.

| Technologie citée explicitement | Offres / 10 |
|---|---|
| GitLab CI/CD | 7 |
| Kubernetes, Docker | 6 |
| AWS | 5 |
| Terraform | 4 |
| Ansible | 4 |
| Prometheus / Grafana | 4 |
| SAST / DAST / SCA | 3 |
| Python / Bash | 3 |
| Trivy | 2 |
| SonarQube | 2 |
| Vault / OpenBao | 2 |
| ArgoCD | 2 |
| **Un framework front-end, quel qu'il soit** | **2** |

Le signal le plus utile est une absence : deux offres sur dix nomment un framework front, et
aucun ne revient deux fois (React, Vue et Angular une fois chacun). Un DevSecOps n'est pas
recruté sur son front-end.

## Stack retenue

| Couche | Choix | Justification |
|---|---|---|
| Front-end | React + TypeScript, une page | Lisibilité immédiate pour un recruteur. Sert de cible à sécuriser (dépendances, CSP, lint), pas de vitrine. |
| Back-end | Python / FastAPI, trois endpoints | Python est le langage de scripting attendu partout. Écosystème sécurité direct (bandit, pip-audit, semgrep). Go écarté : coût d'apprentissage non justifié pour ce projet. |
| IaC | Terraform (providers kind, kubernetes, helm) | Objectif d'apprentissage principal. 4 offres / 10. Pilote le cluster local, pas un cloud (ADR 0004). |
| Orchestration | Kubernetes via kind (local) | Coût zéro, reproductible. Toute la sécurité K8s se démontre en local. |
| Registre | GitHub Container Registry | Authentification par le token OIDC de la CI : aucun secret statique. |
| CI/CD | GitHub Actions (référence) + GitLab CI (miroir) | GitLab CI est le dénominateur commun (7/10) ; GitHub est là où les recruteurs regardent. |
| Sécurité | Trivy, semgrep, bandit, gitleaks, Checkov, Cosign, Kyverno | SAST, SCA, scan d'image, scan IaC, signature, policy-as-code. |
| Observabilité | Prometheus + Grafana | 4 offres / 10. |

## Contraintes assumées

- Kubernetes en local via kind — [ADR 0002](../adr/0002-kubernetes-local-terraform-aws.md).
- Aucun fournisseur cloud : Terraform pilote le cluster local, registre GHCR —
  [ADR 0004](../adr/0004-terraform-sans-fournisseur-cloud.md), qui remplace le volet AWS de
  l'ADR 0002 (décidé au jalon 2, voir chapitre 2).
- Développement soirs et week-ends, six jalons sur six à huit semaines.
