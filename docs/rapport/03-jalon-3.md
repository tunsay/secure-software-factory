# Chapitre 3 — Jalon 3 : l'application dans le cluster, puis le cloisonnement

*28 septembre – 3 octobre 2026 — 3a : l'app servie par le cluster, sept incidents, une faille de
la CI trouvée en chemin · 3b : le cloisonnement, mesuré avant et après*

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

Même méthode qu'au jalon 2 : **une seule commande**, `make isolation-proof`, lancée avant puis
après le durcissement. Elle se place du point de vue d'un attaquant qui a pris la main sur le
pod api (par une dépendance vulnérable, par exemple) et pose huit questions : où peut-il aller,
et que peut-il faire avec l'identité du pod ? Les sondes sont en lecture seule.

### Avant — l'état par défaut de Kubernetes (mesuré le 3 octobre)

```
############ RÉSEAU ############
== 1. api -> web : mouvement latéral
OUVERT   HTTP 200 depuis http://web:8080/healthz
== 2. api -> Internet : exfiltration, téléchargement d'outil
OUVERT   HTTP 200 depuis https://example.com
== 3. pod d'un autre namespace (default) -> api
OUVERT   réponse de api.ssf depuis default
== 4. web -> api : flux légitime
OUVERT   réponse de api depuis web
== 5. navigateur -> Traefik -> web -> api : chemin complet
OUVERT   127.0.0.1:8081/api/health

############ IDENTITÉ ############
== 6. jeton Kubernetes monté dans le pod api
OUVERT   jeton monté dans /var/run/secrets/kubernetes.io/serviceaccount/
== 7. depuis le pod api, ce jeton s'authentifie auprès de l'API Kubernetes
OUVERT   authentifié auprès de l'API Kubernetes comme system:serviceaccount:ssf:default
== 8. Traefik peut lire les Secrets hors de ce qu'il sert
   Secrets du namespace terraform-state (état Terraform) : yes
   Secrets de tout le cluster                            : yes
```

Huit questions, huit réponses ouvertes. Aucune n'est une erreur de configuration du projet :
c'est le comportement **par défaut** de Kubernetes et du chart Traefik.

- **Réseau plat** (1, 3) : tout pod du cluster joint tout autre pod. Le test réseau du jalon 1
  (sous compose, l'api joignait le front) se retrouve à l'identique dans Kubernetes.
- **Sortie libre** (2) : un attaquant télécharge ses outils et exfiltre ce qu'il trouve.
- **Jeton monté et accepté** (6, 7) : Kubernetes donne à chaque pod un badge d'accès à son API.
  Le compte `default` n'a aucun droit à ce stade — authentifié n'est pas autorisé — mais la porte
  du composant le plus critique du cluster est ouverte : il suffit d'une erreur de RBAC future
  pour que ce badge devienne une clé.
- **Traefik lit tous les Secrets** (8) : le seul composant exposé à l'extérieur peut lire
  l'ensemble des secrets du cluster, état Terraform compris.
- **Témoins** (4, 5) : les flux légitimes. Ils doivent rester ouverts après : un durcissement qui
  casse l'application n'est pas un durcissement, c'est une panne.

### Ce qui a été construit ([ADR 0008](../adr/0008-cloisonnement-reseau-et-droits.md))

| Mesure | Où | Contre quels tests |
|---|---|---|
| 5 NetworkPolicies : tout fermé dans `ssf`, puis Traefik → web, web → api, DNS | Terraform, `platform/network.tf` | 1, 2, 3 |
| Compte `default` sans jeton, dans chaque namespace | Terraform, module `namespace` | 6, 7 |
| Comptes `api` et `web` dédiés, sans jeton, refus répété sur le pod | chart | 6, 7 |
| Traefik en RBAC namespacé : un Role dans `ingress` et `ssf`, plus de ClusterRole | Terraform, `ingress.tf` | 8 |

Les politiques réseau sont dans la plateforme, pas dans le chart : celui qui déploie
l'application (ArgoCD au jalon 5) ne doit pas pouvoir élargir ses propres flux.

Un compromis assumé : en mode namespacé, Traefik ignore les Ingress qui utilisent
`spec.ingressClassName`. L'Ingress porte donc l'annotation `kubernetes.io/ingress.class`, que
Kubernetes signale comme dépréciée. Une annotation dépréciée contre la lecture de tous les
Secrets du cluster par le composant le plus exposé : la sécurité l'emporte.

### Après — premier passage, sur le poste (même commande)

```
== 1. api -> web          OUVERT   HTTP 200 depuis http://web:8080/healthz
== 2. api -> Internet     OUVERT   HTTP 200 depuis https://example.com
== 3. default -> api      OUVERT   réponse de api.ssf depuis default
== 4. web -> api          OUVERT   réponse de api depuis web
== 5. chemin complet      OUVERT   127.0.0.1:8081/api/health
== 6. jeton monté         BLOQUÉ   FileNotFoundError: aucun jeton dans /var/run/secrets/kubernetes.io/serviceaccount/
== 7. jeton accepté       BLOQUÉ   FileNotFoundError: [Errno 2] No such file or directory: '.../token'
== 8. Traefik, Secrets    terraform-state : no   ·   tout le cluster : no
```
(sortie condensée, une ligne par test)

| | Avant | Après | |
|---|---|---|---|
| 6. Jeton monté dans le pod | oui | **non** | ✅ |
| 7. Jeton accepté par l'API Kubernetes | oui | **impossible** | ✅ |
| 8. Traefik lit les Secrets hors de son périmètre | oui | **non** | ✅ |
| 4, 5. Flux légitimes | ouverts | ouverts | ✅ |
| 1, 2, 3. Flux interdits | ouverts | **ouverts** | ❌ |

**L'identité est cloisonnée. Le réseau ne l'est pas**, alors que les cinq NetworkPolicies ont été
créées sans la moindre erreur.

### La protection qui n'existait que sur le papier

C'est l'enseignement principal du jalon, et il n'aurait jamais été vu sans le test.

Diagnostic, en lecture seule : les pods kindnet (le composant réseau de kind) tournent, mais leurs
journaux bouclent sur la même erreur — `"syncing nftables rules" error`, puis `"Dropping out of
the queue"`. Et le noyau WSL2 :

```
CONFIG_NETFILTER_NETLINK_QUEUE=y
CONFIG_NF_TABLES=y
# CONFIG_NFT_QUEUE is not set
```

kindnet applique les NetworkPolicies avec des règles nftables qui utilisent l'instruction `queue`.
Le noyau WSL2 de Microsoft ne la fournit pas. Les règles sont refusées, kindnet abandonne, et le
trafic passe sans filtre. Rien ne remonte à Kubernetes : les objets NetworkPolicy restent
« valides ». Quatre couches séparent le symptôme de la cause (NetworkPolicy → kindnet → nftables
→ noyau), comme pour l'incident cgroup v1 du jalon 2.

**Décision ([ADR 0009](../adr/0009-preuve-reseau-en-ci-ephemere.md))** : kindnet est conservé, et
le cloisonnement réseau est prouvé sur un **cluster éphémère en CI**, dont le noyau Ubuntu fournit
`NFT_QUEUE`. Le workflow `e2e` construit le cluster avec le même `make infra-up` qu'en local, puis
`make isolation-check` exige les huit verdicts attendus et échoue sur le moindre écart. Calico
(noyau WSL2 vérifié compatible) reste la voie si le poste doit un jour filtrer le réseau.

### Après — sur le cluster éphémère de la CI

Workflow `e2e`, run 37126660256, commit `a0c1a08`, 3 octobre : cluster construit de zéro par le
même `make infra-up`, **en 1 min 48 s** tout compris. Extraits des journaux (`gh run view --log`) :

```
6.17.0-1022-azure
CONFIG_NETFILTER_NETLINK_QUEUE=m
CONFIG_NFT_QUEUE=m                       ◄ la fonction absente du noyau WSL2

BLOQUÉ   URLError: <urlopen error timed out>                       1. api -> web
BLOQUÉ   URLError: <urlopen error [Errno 101] Network is unreachable>   2. api -> Internet
BLOQUÉ   aucune réponse de api.ssf                                  3. default -> api
OUVERT   réponse de api depuis web                                  4. web -> api
OUVERT   127.0.0.1:8081/api/health                                  5. chemin complet
BLOQUÉ   FileNotFoundError: aucun jeton dans /var/run/secrets/kubernetes.io/serviceaccount/
BLOQUÉ   FileNotFoundError: [Errno 2] No such file or directory: '.../token'
   Secrets du namespace terraform-state (état Terraform) : no
   Secrets de tout le cluster                            : no

attendu : BLOQUÉ BLOQUÉ BLOQUÉ OUVERT OUVERT BLOQUÉ BLOQUÉ no no
obtenu  : BLOQUÉ BLOQUÉ BLOQUÉ OUVERT OUVERT BLOQUÉ BLOQUÉ no no
ISOLATION CONFORME
```

Le point le plus parlant est la paire 1 / 4 : **web joint api, api ne joint pas web**. Même réseau,
mêmes pods, flux refusé dans un sens et accepté dans l'autre. Ce n'est pas une panne du réseau,
c'est une politique appliquée. `make app-proof` passe aussi dans la foulée : l'application sert
toujours ses pages derrière ce cloisonnement.

Limite honnête : en CI, seul l'« après » est mesuré. L'« avant » l'a été sur le poste. Pour le
test 2, le message `Network is unreachable` est cohérent avec un refus, mais rien dans ce run ne
prouve qu'un pod du runner aurait atteint Internet sans politique. Mesurer l'avant **et** l'après
dans le même run (appliquer la plateforme sans les politiques, mesurer, puis avec) fermerait ce
doute.

### Synthèse du jalon 3b

| | Avant | Après, poste (WSL2) | Après, CI (noyau Ubuntu) |
|---|---|---|---|
| 1. api → web | ouvert | ouvert (I8) | **bloqué** |
| 2. api → Internet | ouvert | ouvert (I8) | **bloqué** |
| 3. autre namespace → api | ouvert | ouvert (I8) | **bloqué** |
| 4, 5. flux légitimes | ouverts | ouverts | ouverts |
| 6. jeton monté | oui | **non** | **non** |
| 7. jeton accepté par l'API | oui | **impossible** | **impossible** |
| 8. Traefik lit tous les Secrets | oui | **non** | **non** |

La CI vérifie désormais ce tableau à chaque changement d'infrastructure, et chaque lundi.

### Ce qui a cassé, et ce que ça a appris (3b)

**8. Des NetworkPolicies acceptées, et ignorées.** Cinq politiques créées sans erreur, pods
prêts, `apply` vert — et aucun flux bloqué. Le noyau WSL2 n'a pas `NFT_QUEUE`, kindnet ne peut pas
écrire ses règles et laisse tout passer, sans rien signaler à Kubernetes. Diagnostic en lecture
seule (journaux kindnet, `/proc/config.gz`), contre-épreuve en CI sur un noyau qui l'a : appliquées.
*Leçon : « créé sans erreur » ne dit rien de « appliqué ». Seul un test négatif le prouve.*

**9. La CI passe au rouge sans qu'une ligne ne change.** Trois avis de sécurité publiés entre deux
pushes sur `brace-expansion`, dépendance indirecte d'ESLint. Dépendance de développement, absente
de l'image : risque quasi nul en production. Mais le job de publication est passé en `skipped` :
**aucune image n'est partie**. C'est la correction de l'incident 7, vérifiée en conditions réelles.
Corrigé par `npm audit fix` sans `--force` (5.0.9 → 5.0.12).
*Leçon : la connaissance des vulnérabilités avance même quand le code ne bouge pas.*

---

## État en fin de jalon

- **3a** : l'application tourne dans le cluster derrière Traefik, sans aucune exception à PSS
  restricted, exposée sur `127.0.0.1` uniquement (`make app-proof`).
- **3b** : réseau fermé par défaut dans `ssf`, aucun jeton Kubernetes dans les pods applicatifs,
  Traefik limité aux namespaces qu'il sert (`make isolation-proof`).
- Preuve automatisée : workflow `e2e`, cluster éphémère construit par le même `make infra-up`,
  `make isolation-check` exige les huit verdicts. À chaque changement d'infrastructure et chaque
  lundi.
- CI : publication des images conditionnée à **tous** les contrôles (incident 7), vérifiée en
  conditions réelles (incident 9).
- Trois ADR : 0007 (Traefik, NodePort), 0008 (cloisonnement), 0009 (preuve en CI).
- Neuf incidents documentés, dont aucun dans le code de l'application.

---

## Ce qui reste ouvert, et pourquoi

| Point | Statut | Traitement prévu |
|---|---|---|
| ~~Réseau plat entre pods~~ | **fermé** dans `ssf` (3b) | — |
| ~~Jeton de ServiceAccount monté dans les pods~~ | **fermé** (3b) | — |
| ~~Traefik lit tous les Secrets du cluster~~ | **fermé** (3b) | — |
| NetworkPolicies non appliquées sur le poste (WSL2 sans `NFT_QUEUE`) | assumé (ADR 0009) | Calico si le poste doit filtrer ; noyau WSL2 vérifié compatible |
| En CI, l'« après » seul est mesuré | ouvert | mesurer avant et après dans le même run e2e |
| Namespaces `ingress` et `security` sans NetworkPolicy | ouvert | à étendre, `security` avant Kyverno (jalon 5) |
| Traefik lit encore les Secrets de `ssf` et `ingress` | limite du chart | `rbac.secretResourceNames`, comportement à vérifier |
| Annotation `kubernetes.io/ingress.class` dépréciée | assumé (ADR 0008) | réévaluer avec Gateway API |
| Provider kind : clé privée en clair au plan | limite de l'outil | ne jamais capturer ce plan ; à consigner dans un ADR |
| Pas de HPA | assumé : API à état en mémoire, pas de metrics-server | jalon 6 avec les métriques |
| `ubuntu-latest` passe à Ubuntu 26 le 19/10 (workflow `ci`) | à traiter | épingler avant cette date (`e2e` déjà en `ubuntu-24.04`) |
| `kubectl` 1.37 sur le runner, cluster 1.35 | à surveiller | installer un `kubectl` aligné si une commande diverge |
| Node 22 sur le poste, Node 24 en CI et dans l'image | écart d'environnement | aligner le poste |
| Images tirées par tag (SHA de commit), pas par digest | ouvert | jalon 4 |
