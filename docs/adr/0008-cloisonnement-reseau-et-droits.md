# ADR 0008 — Cloisonnement : politiques réseau et droits portés par la plateforme

**Statut** : accepté · **Date** : 2026-10-03 · **Complète** l'ADR 0007 (droits de Traefik)

## Contexte

Mesure du 3 octobre (`make isolation-proof`, avant durcissement) : réseau plat entre tous les
pods du cluster, sortie Internet libre, jeton Kubernetes monté et accepté dans chaque pod, et
Traefik — seul composant exposé à l'extérieur — autorisé à lire tous les Secrets du cluster
(ClusterRole par défaut de son chart). Rien de tout cela n'est une erreur : ce sont les défauts
de Kubernetes et du chart.

## Décision

1. **NetworkPolicies en Terraform** (`platform/network.tf`), pas dans le chart de l'application.
   Tout est fermé dans `ssf` (entrée et sortie), puis trois flux sont ouverts : Traefik → web,
   web → api, DNS vers CoreDNS. Celui qui déploie l'application (ArgoCD au jalon 5) ne doit pas
   pouvoir élargir ses propres flux : la politique appartient à la plateforme.
2. **Pas de jeton par défaut.** Le compte `default` de chaque namespace créé par le module
   `namespace` a `automountServiceAccountToken: false`. Web et api ont chacun leur compte, sans
   jeton, et le pod le refuse aussi (double déclaration volontaire).
3. **Traefik en RBAC namespacé** (`rbac.namespaced: true`) : un Role dans `ingress` et dans
   `ssf`, plus de ClusterRole. Il ne lit plus les Secrets que de ces deux namespaces.

## Conséquence assumée : l'annotation dépréciée

En mode namespacé, Traefik ne lit plus les objets de niveau cluster (IngressClass, nœuds) et
**ignore les Ingress qui référencent une IngressClass** (`spec.ingressClassName`). L'Ingress de
l'application porte donc l'annotation `kubernetes.io/ingress.class: traefik`, que l'API Kubernetes
signale comme dépréciée depuis la 1.18.

Arbitrage : une annotation dépréciée, mais toujours prise en charge par Traefik, contre la lecture
de tous les Secrets du cluster par le composant le plus exposé. Le risque de sécurité l'emporte
sur la propreté de l'API. À réévaluer avec Gateway API, qui sépare les droits autrement.

## Alternatives écartées

- **Garder la ClusterRole du chart** : c'est l'« avant » mesuré, Secrets de tout le cluster.
- **RBAC écrit à la main** (ClusterRole limitée aux IngressClass + Roles par namespace) : garderait
  `spec.ingressClassName`, mais en se substituant au chart sur un point que l'éditeur ne
  maintient pas dans cette combinaison. Plus de code à maintenir, pour un gain de forme.
- **NetworkPolicies dans le chart** : l'application porterait ses propres règles d'isolement.

## Limites connues

- Traefik lit encore les Secrets de `ssf` et `ingress`, dont les Secrets de release Helm
  (manifests et valeurs, aucun secret applicatif aujourd'hui). `rbac.secretResourceNames`
  permettrait de restreindre par nom, au prix d'un comportement non vérifié du contrôleur.
- Les namespaces `ingress` et `security` n'ont pas encore de politique réseau. `ssf` d'abord :
  c'est là que tourne le code exposé.
- Une NetworkPolicy ignorée par le réseau ne produit aucune erreur. La garantie est le test, pas
  le code : `make isolation-proof`.
