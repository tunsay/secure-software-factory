# ADR 0007 — Ingress : Traefik exposé par NodePort, sans exception PSS

**Statut** : accepté · **Date** : 2026-09-28

## Contexte

Le jalon 3 expose l'application hors du cluster kind. Il faut un ingress controller, et un
moyen de faire arriver le trafic de l'hôte jusqu'à lui.

Deux constats, vérifiés avant de choisir :

- **ingress-nginx, le contrôleur des tutoriels, est retiré** depuis mars 2026 : dépôt archivé,
  plus de release ni de correctif de sécurité (annonce du projet Kubernetes, novembre 2025).
  L'installer aujourd'hui, c'est déployer un composant exposé à Internet qui ne sera plus jamais
  corrigé.
- **La recette kind habituelle repose sur `hostPort`** : le contrôleur ouvre directement les
  ports 80/443 du nœud control-plane. Pod Security Standards interdit `hostPort` dès le niveau
  `baseline`. Il faudrait un namespace `privileged`, que le module `namespace` refuse par
  construction (jalon 2).

## Décision

- **Traefik** (chart officiel, version épinglée), installé par Terraform (`helm_release`) dans
  un namespace `ingress` créé par le module `namespace`, en **PSS restricted**. Son chart est
  conforme sans modification : UID 65532, système de fichiers en lecture seule, capacités
  retirées, seccomp `RuntimeDefault`.
- **Exposition par Service NodePort** (30080/30443) au lieu de `hostPort`. kube-proxy ouvre le
  port sur chaque nœud ; la couche `cluster` ne relie que celui du control-plane à l'hôte.
- **Publication sur `127.0.0.1` uniquement** (8081/8444) : l'application n'est pas joignable
  depuis le réseau local. kind publie sur `0.0.0.0` par défaut.
- **API Ingress standard** (`networking.k8s.io/v1`), pas les CRD propres à Traefik, qui ne sont
  pas installées. Classe `traefik` explicite, jamais classe par défaut.
- Réduction de surface : tableau de bord désactivé, aucun appel sortant vers traefik.io.

## Alternatives écartées

- **ingress-nginx** : fin de vie, voir plus haut.
- **Gateway API** (successeur d'Ingress) : c'est la cible à terme. Elle demande d'installer ses
  CRD à part (le chart Traefik ne les fournit pas) et ajoute trois objets (GatewayClass,
  Gateway, HTTPRoute) pour une seule route. L'API Ingress reste supportée, elle est seulement
  gelée. Migration possible plus tard sans changer de contrôleur : Traefik gère les deux.
- **hostPort dans un namespace dérogatoire** : c'est créer une exception de sécurité pour un
  besoin qui a une solution sans exception.

## Conséquences

- Aucun pod du cluster, ingress compris, ne tourne en dehors de PSS restricted.
- Le patch kubeadm `ingress-ready=true` de la couche `cluster` disparaît. C'était le point le
  plus fragile du cluster (format dépendant de la bibliothèque kind embarquée, rapport jalon 2).
- Le changement de ports de la couche `cluster` impose une recréation du cluster, sans
  conséquence : il est jetable.
- Le NodePort est ouvert sur tous les nœuds. Sans effet ici (seul le control-plane est relié à
  l'hôte), mais à retenir sur un vrai cluster : c'est ce que les NetworkPolicies et le pare-feu
  des nœuds doivent borner.
- Traefik dispose par défaut de droits en lecture sur tout le cluster (ClusterRole). Le
  restreindre aux namespaces servis relève du RBAC minimal du jalon 3b.
