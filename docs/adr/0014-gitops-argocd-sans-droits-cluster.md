# ADR 0014 — GitOps : ArgoCD déploie l'application depuis ce dépôt, sans droits sur le cluster

**Statut** : accepté · **Date** : 2026-10-04 · **Écart au plan** : pas de dépôt de manifests séparé

## Contexte

Mesure du 4 octobre (`make drift-proof`, avant, journal du jalon 5) : cinq modifications
manuelles de l'application — `APP_ENV` changé, front à 0 réplique, Service de l'API supprimé,
variable ajoutée, objet étranger créé — **persistent toutes** après 60 s. Et `terraform plan`
répond « no differences » : Terraform ne compare que l'état de sa release Helm, pas les objets
réels. L'application est en panne et personne ne le voit.

Par défaut, le chart d'Argo CD donne à son contrôleur une ClusterRole `*` sur `*` (et
`nonResourceURLs: *`) : l'outil de déploiement devient le composant le plus privilégié du
cluster. Un ArgoCD compromis, ou un commit malveillant, donnerait tout le cluster.

## Décision

1. **Argo CD v3.5.3** (chart `argo-cd` 10.9.2, délai de carence de 7 jours respecté), installé
   par Terraform dans un namespace `argocd`, PSS restricted (le chart est conforme par défaut).
2. **Source : ce dépôt**, chart `k8s/chart`, valeurs `k8s/chart/values-dev.yaml`. Déployer une
   version = un commit sur ce fichier. Synchronisation automatique avec `prune` et `selfHeal`.
3. **Pas de dépôt de manifests séparé** (écart au plan, décision de Tunsay) :
   - le workflow e2e fait déployer par ArgoCD **exactement le commit testé** ;
   - aucun jeton d'écriture vers un autre dépôt : la CI reste en lecture seule (ADR 0011), elle
     ne peut pas déployer ; déployer reste un commit humain ;
   - en équipe, on séparerait les dépôts, ou on protégerait `k8s/` par CODEOWNERS.
4. **Aucun droit de cluster pour ArgoCD** (`createClusterRoles: false`). Le cluster local est
   déclaré restreint au namespace `ssf`, sans identifiants : ArgoCD utilise le compte de son pod.
   Ses droits dans `ssf` sont portés par Terraform (ADR 0008) : écrire les Deployments,
   Services, ServiceAccounts et Ingress ; lire les ReplicaSets et les pods. Rien sur les
   Secrets, les Roles, les NetworkPolicies ni les quotas.
5. **Second verrou, côté ArgoCD** : le projet `ssf` n'admet qu'une source (ce dépôt), qu'une
   destination (`ssf`), aucun objet de niveau cluster, et les seuls types d'objets du chart.
6. **Aucun compte** : administrateur désactivé, interface anonyme en lecture seule, non exposée
   (port-forward seulement). Aucun mot de passe n'existe ; seul Git déploie.
7. **Terraform garde la plateforme** : namespaces, ingress, NetworkPolicies, Kyverno, et les
   droits d'ArgoCD lui-même. Traefik publie `127.0.0.1` dans le statut des Ingress : sans
   adresse publiée, ArgoCD juge un Ingress « Progressing » indéfiniment (règle lue dans le
   source v3.5.3).

## Conséquences

- Attendu, à confirmer par la mesure (`make drift-proof`, après) : une modification manuelle
  d'un objet que le dépôt décrit est annulée en quelques secondes.
- Attendu aussi : ArgoCD n'annule pas ce que le dépôt ne décrit pas (un champ ajouté, un objet
  étranger). Ce sont d'autres verrous qui couvrent ce cas : droits Kubernetes, Kyverno.
- Le déploiement devient asynchrone : `make infra-up` attend qu'ArgoCD ait synchronisé
  l'application (`make app-wait`).
- ArgoCD lit GitHub : un dépôt injoignable gèle les déploiements, sans arrêter l'application.
- La CI e2e prouve à chaque changement d'infrastructure que les modifications décrites sont
  annulées et que les droits d'ArgoCD restent bornés à `ssf` (`make drift-check`).
