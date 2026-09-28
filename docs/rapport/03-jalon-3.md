# Chapitre 3 — Jalon 3 : l'application dans le cluster, puis le cloisonnement

*28 septembre 2026 — 3a : l'app servie par le cluster, sept incidents, une faille de la CI
trouvée en chemin · 3b : à venir*

## Objectif du jalon

Le jalon 2 a durci un cluster **vide** : il prouve qu'un pod malveillant est refusé, pas qu'une
vraie application peut vivre sous ces règles. Et Pod Security Standards protège le **nœud**
contre un pod ; il ne protège ni les pods les uns des autres, ni l'API Kubernetes contre un pod.

Le jalon est découpé en deux livrables, présentables séparément :

- **3a** — l'application tourne dans le cluster, installée par Terraform, sans aucune exception
  aux règles posées au jalon 2 ;
- **3b** — le cluster est cloisonné : réseau fermé par défaut, droits réduits au strict minimum.

Méthode inchangée : mesurer l'**avant**, durcir, prouver l'**après** avec la même commande.

---

## 3a — L'application tourne dans le cluster

### Deux vérifications qui ont changé le plan

Le plan prévoyait « un ingress » sans plus de précision. Deux constats, faits **avant** d'écrire
une ligne, ont décidé de la suite ([ADR 0007](../adr/0007-ingress-traefik-nodeport.md)) :

1. **ingress-nginx, le contrôleur de presque tous les tutoriels kind, est retiré** depuis mars
   2026 : dépôt archivé, plus aucun correctif de sécurité. L'installer, c'est exposer au réseau un
   composant qui ne sera plus jamais corrigé. → **Traefik**, maintenu, version épinglée.
2. **La recette kind classique ouvre les ports du nœud avec `hostPort`**, interdit par Pod
   Security Standards dès le niveau `baseline`. Il aurait fallu un namespace `privileged`, que le
   module Terraform du jalon 2 refuse par construction. → **Service NodePort** : le contrôleur
   reste un pod ordinaire, en PSS `restricted`.

Résultat : **aucun pod du cluster, ingress compris, ne tourne hors de PSS restricted**. Aucune
exception n'a été nécessaire — ce qui vaut mieux qu'une exception bien documentée.

### Ce qui a été construit

```
infra/terraform/
  cluster/        ports NodePort, écoute sur 127.0.0.1, patch kubeadm fragile supprimé
  platform/
    main.tf       + namespace ingress (PSS restricted, même module qu'au jalon 2)
    ingress.tf    Traefik par helm_release : sans CRD, sans tableau de bord, sans appel sortant
    app.tf        l'app par helm_release, depuis le chart du dépôt
k8s/chart/        chart maison : Deployments api et web, Services, Ingress
```

| Composant | Répliques | Durcissement |
|---|---|---|
| Traefik | 1 | UID 65532, lecture seule, capacités retirées, seccomp — chart conforme sans modification |
| web (nginx) | 2, une par worker | UID 101, lecture seule, capacités retirées, seccomp, `emptyDir` en mémoire pour `/tmp` et le cache |
| api (FastAPI) | 1 (stockage en mémoire : deux répliques donneraient deux listes différentes) | UID 10001, lecture seule, capacités retirées, seccomp |

Le chart refuse de s'installer sans tag d'image, ou avec autre chose qu'un SHA de commit complet.
Il est vérifié à trois endroits : hook pre-commit, `make infra-lint`, CI (`helm lint --strict`,
rendu, puis Trivy sur les manifests rendus : **0 mauvaise configuration**).

### Chemin d'une requête

```
navigateur ─► 127.0.0.1:8081 ─► NodePort 30080 ─► Traefik ─► Service web ─► nginx
                                                                              │ /api/
                                                                              ▼
                                                                   Service api ─► FastAPI
```

Seul `web` est derrière l'Ingress. L'API n'a **aucune route directe** depuis l'extérieur du
cluster : on ne l'atteint qu'à travers le proxy nginx.

### Preuve — `make app-proof`

```
$ kubectl -n ssf get pods -o wide
NAME                   READY   STATUS    RESTARTS   AGE   NODE
api-584cc9757f-ctm5f   1/1     Running   0          42s   ssf-dev-worker
web-bf97b4d87-44h8g    1/1     Running   0          42s   ssf-dev-worker
web-bf97b4d87-776ft    1/1     Running   0          42s   ssf-dev-worker2

$ curl -fsS http://127.0.0.1:8081/healthz
ok
$ curl -fsS http://127.0.0.1:8081/api/health
{"status":"ok","version":"0.1.0","env":"dev"}

$ kubectl -n ssf exec deploy/web -- id
uid=101(nginx) gid=101(nginx) groups=101(nginx)
$ kubectl -n ssf exec deploy/api -- id
uid=10001(app) gid=10001(app) groups=10001(app)

$ kubectl -n ssf exec deploy/web -- sh -c 'echo defaced > /usr/share/nginx/html/index.html'
sh: can't create /usr/share/nginx/html/index.html: Read-only file system
command terminated with exit code 1
```

Les deux répliques du front sont sur deux nœuds différents : la perte d'un worker ne coupe pas
le site. Aucun processus root. Un attaquant qui obtiendrait un shell dans le front ne peut ni
défigurer le site, ni déposer un outil.

### Avant / après — de quoi on est protégé

#### 1. Exposition réseau : du réseau local à ce seul poste

**Avant** (cluster du jalon 2, `docker ps`, colonnes réduites) :

```
PORTS                                                                    NAMES
0.0.0.0:8081->80/tcp, 0.0.0.0:8444->443/tcp, 127.0.0.1:43221->6443/tcp   ssf-dev-control-plane
```

`0.0.0.0` : toutes les interfaces. Sur le Wi-Fi d'un café, n'importe quel voisin de réseau
pouvait atteindre l'application.

**Après** :

```
$ docker port ssf-dev-control-plane
6443/tcp -> 127.0.0.1:39245
30080/tcp -> 127.0.0.1:8081
30443/tcp -> 127.0.0.1:8444
```

Les trois ports, API Kubernetes comprise, n'écoutent que sur la boucle locale. Une ligne de
Terraform par port (`listen_address = "127.0.0.1"`).

#### 2. L'ingress controller : du composant abandonné au composant maintenu

| | Avant (tutoriel kind) | Après |
|---|---|---|
| Contrôleur | ingress-nginx, **plus de correctif de sécurité depuis mars 2026** | Traefik 3.7, chart 41.6.0 épinglé |
| Namespace | `privileged`, pour autoriser `hostPort` | `restricted`, comme l'application |
| Surface | CRD, tableau de bord, vérification de version en ligne | API Ingress standard seule, rien d'autre |
| Classe d'ingress | classe par défaut : tout Ingress est servi | classe explicite : un Ingress qui ne la nomme pas n'est servi par personne |

La preuve que Traefik tourne bien en `restricted` : l'API server l'a admis. Le namespace
`ingress` porte le label `pod-security.kubernetes.io/enforce: restricted`, et un pod non
conforme y serait refusé comme `node-pwn` l'a été au jalon 2.

#### 3. La CI laissait partir une image malgré un échec de sécurité

Trouvé en analysant pourquoi `semgrep` était rouge (incidents 6 et 7 ci-dessous).

**Avant** : le job qui construit et **publie** les images sur GHCR n'attendait que `api` et
`web`. Historique réel de `main` :

| Commit | Date | semgrep | Image publiée sur GHCR |
|---|---|---|---|
| `c41a991` | 18/09 | ✅ | oui |
| `fde5893` | 18/09 | ❌ | **oui** |
| `8a5d1dc` | 28/09 | ❌ | **oui** — c'est celle que le jalon 3a déploie |

Colonne semgrep : historique des runs via l'API GitHub. Colonne GHCR : manifeste des images
`ssf-api` et `ssf-web` de chaque commit, demandé sans authentification — HTTP 200 dans les six cas.

Le README annonçait une chaîne qui « bloque ». Elle ne bloquait pas : un secret détecté par
gitleaks aurait laissé partir l'image de la même façon.

**Après** : `needs: [secrets, api, web, semgrep, iac]`. Horaires réels du premier run corrigé
(`654dc37`), lus via l'API GitHub :

```
11:21:33 -> 11:22:24  terraform + chart     (le dernier contrôle à finir)
11:21:33 -> 11:21:42  gitleaks
11:21:34 -> 11:21:52  web
11:21:34 -> 11:22:01  api
11:21:34 -> 11:22:07  semgrep
11:22:26 -> 11:23:46  build + trivy · web   ◄ démarre 2 s après le dernier contrôle
11:22:27 -> 11:23:17  build + trivy · api
```

Même défaut, même correction dans le miroir GitLab CI.

#### Synthèse

| | Avant | Après |
|---|---|---|
| Exposition | `0.0.0.0` : tout le réseau local | `127.0.0.1` : ce poste uniquement |
| Ingress controller | abandonné, namespace `privileged` | maintenu, namespace `restricted` |
| API applicative | exposée en direct (port 8000 sous compose) | aucune route externe |
| Conteneurs | — | non-root, lecture seule, sans capacités, prouvé par `make app-proof` |
| Publication des images | possible avec un contrôle de sécurité rouge | seulement si **tous** les contrôles sont verts |

### Ce qui a cassé, et ce que ça a appris

Sept incidents. Aucun dans le code de l'application. Détail complet dans le
[journal du jalon](journal-jalon-3.md).

**1. Une clé de chart renommée.** `logs.access` est devenu `accessLog` dans le chart Traefik 41.
Le schéma JSON du chart a refusé la clé inconnue **au `plan`**, avant toute création. Sans ce
schéma, la clé aurait été ignorée en silence.
*Leçon : une option se vérifie dans le `values.yaml` de la version épinglée, pas dans un résumé.*

**2. Le plan affiche la clé privée administrateur du cluster.** Au remplacement du cluster, le
provider `tehcyx/kind` affiche en clair la clé privée et le kubeconfig complets : il ne les
déclare pas `sensitive`, et Terraform ne peut pas le faire à sa place. Portée faible (cluster
local, clé détruite dans la foulée), mais c'est la fuite typique d'un log de CI ou d'une capture.
*Leçon : `sensitive` est une promesse du provider. Lire un plan, c'est aussi vérifier ce qu'il
laisse fuiter.*

**3. Une option expérimentale sur le chemin de déploiement.** `experiments.manifest` du provider
helm, activée pour lire les manifests au plan, a fait échouer l'apply (« Provider produced
inconsistent final plan ») : le namespace n'existait pas encore au moment du plan. Bug connu.
Remplacée par une empreinte SHA-256 du chart.
*Leçon : « experimental » est un avertissement, pas une étiquette.*

**4. `check-yaml` ne sait pas lire un template Helm.** `{{- include }}` n'est pas du YAML avant
rendu. Le template est exclu de `check-yaml` **et** couvert par un nouveau hook `chart-lint`.
*Leçon : on n'exclut un fichier d'un contrôle que si un contrôle adapté le couvre.*

**5. « Private key found » dans le journal de bord.** En documentant l'incident 2, le journal
citait l'en-tête d'une clé privée. Reformulé ; le fichier n'a pas été exclu du hook. Gitleaks,
passé juste avant, n'avait rien vu : deux outils, deux sensibilités.
*Leçon : un document de sécurité parle de secrets sans en reproduire la forme.*

**6. CI rouge depuis dix jours.** Semgrep bloquait sur deux fichiers du jalon 2 : l'extrait de
`/etc/shadow` du rapport (la preuve de l'évasion) et le manifeste d'attaque, volontairement
privilégié. Dérogations **à la ligne** (`nosemgrep`) et justifiées dans
`security/exceptions.yaml`, avec expiration. Premier essai raté : semgrep n'accepte le
commentaire sur la ligne précédente que si elle ne contient rien d'autre.
*Leçon : la documentation passe par les mêmes contrôles que le code — et une CI rouge que
personne ne regarde ne contrôle plus rien.*

**7. La publication n'attendait pas les contrôles de sécurité.** Voir l'avant/après n° 3.
*Leçon : en CI, le graphe de dépendances des jobs **est** la politique de sécurité.*

### État en fin de 3a

- `make infra-up` : cluster, trois namespaces `restricted`, Traefik et l'application, en une commande
- `make app-proof` : l'application répond sur `127.0.0.1:8081`, pods non-root en lecture seule
- Chart vérifié en pre-commit, en local et en CI ; 0 mauvaise configuration Trivy
- CI verte, 7 jobs, publication conditionnée à **tous** les contrôles
- ADR 0007 ; deux dérogations semgrep tracées dans `security/exceptions.yaml`

---

## 3b — Le cluster est cloisonné

*À venir.* Même méthode : l'avant est mesuré **avant** tout durcissement.

| Test | Avant attendu | Après attendu |
|---|---|---|
| L'API joint le front (`http://web:8080`) | réussit : réseau plat, comme sous compose au jalon 1 | refusé : NetworkPolicy deny-by-default |
| Le front joint l'API | réussit | réussit : seul flux ouvert |
| Token Kubernetes présent dans le pod | oui, monté par défaut | absent |
| Ce token interroge l'API Kubernetes | à mesurer | impossible, faute de token |
| Droits de Traefik | lecture sur tout le cluster | limités aux namespaces servis |

---

## Ce qui reste ouvert, et pourquoi

| Point | Statut | Traitement prévu |
|---|---|---|
| Réseau plat entre pods et namespaces | ouvert | NetworkPolicies, 3b |
| Token de ServiceAccount monté dans les pods | ouvert | RBAC minimal, 3b |
| Traefik lit tout le cluster (ClusterRole) | ouvert | restreindre aux namespaces servis, 3b |
| Provider kind : clé privée en clair au plan | limite de l'outil | ne jamais capturer ce plan ; à consigner dans un ADR |
| API Ingress gelée, Gateway API à terme | assumé (ADR 0007) | migration possible sans changer de contrôleur |
| Pas de HPA | assumé : API à état en mémoire, pas de metrics-server | jalon 6 avec les métriques |
| `ubuntu-latest` passe à Ubuntu 26 le 19/10 | à traiter | épingler la version du runner avant cette date |
| Images tirées par tag (SHA de commit), pas par digest | ouvert | jalon 4 |
