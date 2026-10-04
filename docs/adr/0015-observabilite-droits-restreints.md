# ADR 0015 — Observabilité de la posture de sécurité, sans composant trop privilégié

**Statut** : accepté · **Date** : 2026-10-04

## Contexte

Mesure du 4 octobre (`make posture-proof`, avant, journal du jalon 6) : sept questions de
sécurité — refus d'admission, synchronisation de l'application, vulnérabilités des images qui
tournent, défauts de configuration, redémarrages, erreurs servies au public, alertes en cours —
restent **sans réponse**. Tous les contrôles des jalons 1 à 6a empêchent ; aucun ne raconte.

Les outils standard, lus dans leurs charts avant d'écrire, sont trop privilégiés par défaut :

- **node-exporter** (kube-prometheus-stack) : pod privilégié (`hostNetwork`, `hostPID`,
  montages du nœud), interdit par PSS restricted ;
- **Grafana** : son « sidecar » reçoit la lecture de **tous les Secrets** du cluster ;
- **trivy-operator** : lecture de tous les Secrets, **création de Jobs dans tous les
  namespaces** — un scanner compromis lancerait un pod privilégié dans `kube-system`.

## Décision

1. **kube-prometheus-stack 91.7.1** dans un namespace `monitoring` (PSS restricted), **sans
   node-exporter** (pas besoin des métriques système des nœuds pour la posture), **sans
   Alertmanager** (personne à prévenir sur un cluster de développement : les alertes restent
   calculées et affichées), sans règles ni cibles par défaut (injoignables sur kind).
2. **Grafana** : droits limités à son namespace, aucun compte (formulaire de connexion désactivé,
   lecture anonyme en lecture seule), accès par port-forward seulement, aucun appel sortant.
   Tableau de bord « posture sécurité » versionné dans `k8s/monitoring`.
3. **trivy-operator 0.34.0** dans `security`, limité au namespace `ssf`, avec des **droits écrits
   dans Terraform** et non ceux du chart (décision de Tunsay) : lecture des objets de `ssf`, Jobs
   de scan dans `security` seulement, aucun Secret hors de son namespace, aucune écriture au
   niveau cluster hors de ses propres rapports.
4. **Sources** : Kyverno (refus), ArgoCD (synchronisation, santé), Traefik (réponses par code),
   kube-state-metrics (redémarrages), trivy-operator (vulnérabilités, configuration), et les
   métriques internes de l'API, lues dans le cluster par une NetworkPolicy dédiée
   (`api-from-monitoring`) puisque nginx les refuse au public depuis le jalon 6a.
5. **Règles d'alerte** `famille=securite`, versionnées : refus d'admission, application
   désynchronisée ou non saine depuis 5 minutes, vulnérabilité critique en production,
   redémarrages en boucle, erreurs 5xx.

## Conséquences

- Les sept questions ont une réponse chiffrée (`make posture-proof`, après).
- Prometheus garde ses droits de lecture standard sur tout le cluster (services, endpoints,
  pods) pour découvrir ses cibles : lecture seule, assumée.
- Plus de charge sur le poste : Prometheus, Grafana, trivy-operator et ses Jobs de scan.
- Une vulnérabilité publiée **après** le déploiement devient visible, ce que la CI ne voit plus.
- Écart au plan : « âge des images » n'est pas affiché (aucune métrique standard ne le donne).
