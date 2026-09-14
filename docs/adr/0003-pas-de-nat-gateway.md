# ADR 0003 — Pas de NAT Gateway

**Statut** : accepté · **Date** : 2026-09-14

## Contexte

Le NAT Gateway est facturé à l'heure (~32 €/mois) même sans trafic. C'est le premier poste
de dépense involontaire des projets Terraform « free tier ».

## Décision

Aucun NAT Gateway. Si une ressource a besoin d'un sous-réseau, elle est placée en sous-réseau
public avec un security group en deny-by-default et des règles d'entrée explicites.

## Conséquences

- Coût : 0 €.
- Le compromis est assumé et documenté : en production réelle, un NAT Gateway ou des
  VPC endpoints seraient la norme. Ce point est un sujet d'entretien, pas une faiblesse cachée.
