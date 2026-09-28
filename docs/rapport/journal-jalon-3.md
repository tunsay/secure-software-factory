# Journal de bord — jalon 3

Notes prises au fil de l'eau, matière première du chapitre `03-jalon-3.md`. Chaque incident :
symptôme, cause, diagnostic, correction, leçon. Chaque livrable : avant / après, et de quoi on
est protégé.

---

## 3a — l'application tourne dans le cluster

### Décisions prises avant d'écrire une ligne (vérifiées, pas supposées)

| # | Constat | Conséquence |
|---|---|---|
| D1 | **ingress-nginx retiré en mars 2026** : dépôt archivé, plus de correctif de sécurité. C'est pourtant le contrôleur de presque tous les tutoriels kind. | Traefik (chart 41.6.0), ADR 0007. |
| D2 | La recette kind classique ouvre les ports 80/443 du nœud avec `hostPort`, **interdit par PSS dès `baseline`**. Il aurait fallu un namespace `privileged`, que notre module refuse. | Service **NodePort** (30080/30443) : le contrôleur est un pod ordinaire, en PSS restricted. Aucune exception. |
| D3 | kind publie les ports sur `0.0.0.0` par défaut : l'app était joignable depuis tout le réseau local (le Wi-Fi d'un café, par exemple). | `listen_address = "127.0.0.1"` dans la couche cluster. |
| D4 | Le chart Traefik crée par défaut un Service `LoadBalancer`. Sur kind, personne ne lui attribue d'IP : `helm_release` avec `wait = true` aurait attendu jusqu'au timeout. | Même correction que D2 (NodePort). Piège évité sans l'avoir rencontré. |
| D5 | Le patch kubeadm `ingress-ready=true` (incident n°2 du jalon 2) ne sert qu'à placer un ingress en `hostPort` sur le control-plane. | Supprimé : le point le plus fragile du cluster disparaît. |
| D6 | Provider `helm` 3.x : syntaxe changée (`kubernetes = { }` et `set = [{ }]` au lieu de blocs). Les exemples en ligne sont majoritairement en 2.x. | Écrit en 3.x, version `~> 3.3`. Valeurs passées en `yamlencode`, plus lisible que des `set`. |
| D7 | Avec un chart **local**, le provider helm ne voit pas une modification des templates si la version du chart ne change pas. | ~~`experiments = { manifest = true }`~~ — abandonné, voir incident I3. Remplacé par une empreinte SHA-256 du chart passée en valeur. |
| D8 | L'API stocke ses items **en mémoire**. Deux répliques = deux listes différentes selon le pod qui répond. | API : 1 réplique. Web (sans état) : 2 répliques, une par worker. Pas de HPA : pas de metrics-server, et l'API ne peut pas monter en charge horizontalement par construction. |
| D9 | nginx relaie `/api/` vers l'hôte `api` (nginx.conf du jalon 1). | Le Service s'appelle exactement `api`. Seul `web` est derrière l'Ingress : **l'API n'a aucune route directe depuis l'extérieur**. |
| D10 | Traefik : CRD, tableau de bord et appels sortants (vérification de version) activés par défaut. | Désactivés. Moins d'objets, moins de droits, pas de trafic sortant inutile. |

### Ce qui a été construit

- `infra/terraform/cluster` : ports NodePort, écoute sur 127.0.0.1, patch kubeadm supprimé.
- `infra/terraform/platform/main.tf` : namespace `ingress` (PSS restricted, module existant).
- `infra/terraform/platform/ingress.tf` : Traefik par `helm_release`.
- `infra/terraform/platform/app.tf` : l'app par `helm_release`, depuis `k8s/chart`.
- `k8s/chart/` : chart maison — Deployments api et web, Services, Ingress.
- `make chart-lint` (helm lint, rendu, trivy sur les manifests) et `make app-proof`.
- ADR 0007.

### Validations passées

- `make chart-lint` : `helm lint --strict` OK, rendu OK, **trivy : 0 mauvaise configuration**
  sur `api.yaml`, `web.yaml`, `ingress.yaml`.
- Recréation du cluster : le plan annonce `must be replaced` à cause de `container_port 80 ->
  30080`, `listen_address = "127.0.0.1"` et de la suppression du patch kubeadm. Nouveau cluster
  en 45 s.
- `make infra-lint` complet : `terraform fmt` sans écart, `validate` OK sur les trois dossiers,
  Checkov sans alerte, trivy **0** sur `cluster` et `platform`.

### Incidents

#### I1 — Le schéma du chart Traefik refuse une clé : `logs` n'existe plus

- **Symptôme** : `make infra-up`, au plan de la couche platform :
  ```
  Error: Error performing dry run install
  values don't meet the specifications of the schema(s) in the following chart(s):
  traefik:
  - at '': additional properties 'logs' not allowed
  ```
- **Cause** : les logs d'accès s'activaient avec `logs.access.enabled` dans les anciennes
  versions du chart. Dans la 41.6.0, la clé est `accessLog.enabled`. La valeur avait été reprise
  d'un résumé de la documentation, pas du fichier `values.yaml` de la version épinglée.
- **Diagnostic** : lecture du `values.yaml` brut de la version 41.6.0 : `log:` (niveau) et
  `accessLog:` (logs d'accès) sont deux blocs de premier niveau. Toutes les autres clés passées
  au chart ont été revérifiées sur ce même fichier.
- **Correction** : `accessLog = { enabled = true }` dans `ingress.tf`.
- **Ce qui a bien marché** : le chart embarque un **schéma JSON** qui refuse toute clé inconnue,
  et le provider helm fait un *dry run* dès le `plan`. L'erreur est tombée **avant** tout
  `apply` : rien n'a été créé à moitié. Sans schéma, la clé aurait été ignorée en silence, et on
  aurait cru avoir des logs d'accès.
- **Leçon** : une option de chart se vérifie dans le `values.yaml` **de la version épinglée**,
  pas dans un tutoriel ni un résumé — les charts renomment leurs clés d'une majeure à l'autre.

#### I2 — Le plan du cluster affiche la clé privée administrateur en clair

- **Constat** (en relisant la sortie de `make infra-up`) : le plan de remplacement du cluster
  affiche en clair `client_key` (une clé privée RSA complète, au format PEM), `client_certificate` et le
  `kubeconfig` complet. Ce sont les identifiants **cluster-admin** : quiconque les possède a
  tous les droits sur le cluster.
- **Cause** : le provider `tehcyx/kind` ne marque pas ces attributs `sensitive`. Terraform
  masque (`(sensitive value)`) uniquement ce que le provider déclare sensible.
- **Portée réelle** : faible ici — cluster local, joignable sur 127.0.0.1 seulement, et la clé
  affichée était celle du cluster **détruit** dans la foulée. Mais c'est exactement le genre de
  fuite qui finit dans un log de CI, une capture d'écran de rapport ou un ticket.
- **Ce qui protège déjà** : la couche cluster ne tourne jamais en CI (seulement `validate`, qui
  ne lit aucun état) ; l'état local est ignoré par git ; aucun `output` n'expose ces attributs.
- **Ce qu'on ne peut pas corriger** : Terraform ne permet pas de rendre sensible un attribut
  qu'un provider a déclaré en clair. Le provider est aussi en cause dans les incidents 2 à 4 du
  jalon 2 : troisième limite constatée, à ajouter à l'ADR 0004 lors d'un prochain ADR.
- **Règle retenue** : ne jamais capturer ni coller un plan de remplacement de la couche cluster
  sans l'avoir expurgé.
- **Leçon** : `sensitive` est une promesse **du provider**. Lire un plan, c'est aussi vérifier ce
  qu'il laisse fuiter.

#### I3 — « Provider produced inconsistent final plan » : l'option expérimentale du provider helm

- **Symptôme** : le plan passe (`11 to add`), les 9 objets des namespaces sont créés, puis :
  ```
  Error: Provider produced inconsistent final plan
  When expanding the plan for helm_release.traefik ... produced an invalid new value for
  .resources: new element "deployment.apps/v1/ingress/traefik" has appeared.
  This is a bug in the provider, which should be reported in the provider's own issue tracker.
  ```
  Même erreur pour le Service et le ServiceAccount de Traefik. Rien n'est installé.
- **Cause** : `experiments = { manifest = true }` (décision D7), activé pour que le plan affiche
  les manifests rendus. Au moment du plan, le namespace `ingress` n'existe pas encore : la liste
  des objets que Traefik va créer (`.resources`) est calculée incomplète. À l'apply, le namespace
  existe, la liste est complète, et Terraform refuse une ressource dont le résultat diffère de ce
  qui a été planifié. Comportement instable connu de cette option (issues #805, #829 du provider).
- **Correction** : option retirée. Le besoin d'origine (voir au plan une modification d'un
  template du chart local) est couvert autrement : une empreinte SHA-256 de tous les fichiers de
  `k8s/chart` est passée au chart (`chartChecksum`). Tout changement de fichier change l'empreinte,
  donc les valeurs, donc le plan.
- **État après l'échec** : cohérent. Les namespaces sont dans l'état Terraform ; les deux
  `helm_release` n'ont jamais été créés. Relancer `make infra-up` n'installe que ce qui manque.
- **Leçon** : « experimental » est un avertissement, pas une étiquette. Un confort de lecture du
  plan ne justifie pas un composant instable sur le chemin de déploiement. Et le message « This is
  a bug in the provider » n'est pas une impasse : c'est une piste, à chercher dans le suivi
  d'issues du provider avant de toucher au code.

#### I4 — Commit refusé : `check-yaml` ne sait pas lire un template Helm

- **Symptôme** : au `git commit`, le hook pre-commit échoue :
  ```
  check yaml...........Failed
  while parsing a flow node
  expected the node content, but found '-'
    in "k8s/chart/templates/web.yaml", line 7, column 7
  ```
  (idem `api.yaml` et `ingress.yaml`). Rien n'est commité.
- **Cause** : un template Helm **n'est pas du YAML** tant qu'il n'est pas rendu. `{{- include
  ... }}` est de la syntaxe Go template ; pour un parseur YAML, `{` ouvre un dictionnaire en ligne,
  et le `-` qui suit est invalide.
- **Correction** : `check-yaml` exclut `k8s/chart/templates/`, et un hook local `chart-lint`
  (`make chart-lint`) prend le relais sur tout fichier du chart : `helm lint --strict`, rendu,
  puis trivy sur le résultat. On ne retire pas un contrôle, on le remplace par celui qui
  comprend le format.
- **Leçon** : chaque outil a un format d'entrée. Exclure un fichier d'un contrôle n'est
  acceptable que si un autre contrôle, adapté, le couvre — sinon c'est un trou.

#### I5 — Commit refusé : « Private key found » dans… le journal

- **Symptôme** : même commit, second hook :
  ```
  detect private key...Failed
  Private key found: docs/rapport/journal-jalon-3.md
  ```
- **Cause** : en documentant l'incident I2, le journal citait l'**en-tête PEM** d'une clé privée
  RSA, tel qu'affiché par le plan. Il n'y avait aucune clé dans le fichier, seulement la ligne
  d'ouverture, mais c'est précisément ce motif que le hook cherche.
- **Correction** : reformulation (« une clé privée RSA complète, au format PEM »). Le fichier
  n'est **pas** exclu du hook : affaiblir un contrôle pour faire passer de la documentation
  serait le mauvais réflexe.
- **Ce que ça montre** : gitleaks, passé juste avant, n'a rien vu — il cherche des secrets
  complets (en-tête **et** corps de clé). `detect-private-key` réagit au seul en-tête. Deux outils,
  deux sensibilités : c'est la défense en profondeur appliquée au poste du développeur. Un faux
  positif ici coûte une reformulation ; un faux négatif aurait coûté une clé publiée.
- **Leçon** : un journal de sécurité parle de secrets ; il doit le faire sans en reproduire la
  forme.

### Avant / après — de quoi on est protégé

| | Avant (tutoriel kind classique) | Après (ce projet) |
|---|---|---|
| Ingress controller | ingress-nginx, **sans correctif de sécurité depuis mars 2026** | Traefik maintenu, version épinglée |
| Privilèges de l'ingress | namespace `privileged` pour autoriser `hostPort` | PSS restricted, comme l'app |
| Exposition réseau | `0.0.0.0` : tout le réseau local | `127.0.0.1` : ce poste uniquement |
| API | exposée sur son propre port (8000 en compose) | aucune route externe, seulement via le proxy du front |
| Conteneurs | écriture possible dans l'image | lecture seule : impossible de défigurer le site ou déposer un binaire |

### Preuve — `make app-proof` (28/09/2026)

Déploiement : `Plan: 2 to add` → Traefik prêt en 1 min 20 s, l'app en 26 s.

```
$ kubectl -n ssf get pods -o wide
NAME                   READY   STATUS    RESTARTS   AGE   IP           NODE
api-584cc9757f-ctm5f   1/1     Running   0          42s   10.244.2.3   ssf-dev-worker
web-bf97b4d87-44h8g    1/1     Running   0          42s   10.244.2.4   ssf-dev-worker
web-bf97b4d87-776ft    1/1     Running   0          42s   10.244.1.2   ssf-dev-worker2
```
Les deux répliques web sont sur deux nœuds différents (`topologySpreadConstraints`).

```
== Front, via Traefik :
$ curl -fsS http://127.0.0.1:8081/healthz
ok
== API, via le proxy nginx du front (l'Ingress ne route que vers web) :
$ curl -fsS http://127.0.0.1:8081/api/health
{"status":"ok","version":"0.1.0","env":"dev"}
```
Chaîne complète : navigateur → 127.0.0.1:8081 → NodePort 30080 → Traefik → Service web →
nginx → Service api → FastAPI.

```
== Identité des processus :
$ kubectl -n ssf exec deploy/web -- id
uid=101(nginx) gid=101(nginx) groups=101(nginx)
$ kubectl -n ssf exec deploy/api -- id
uid=10001(app) gid=10001(app) groups=10001(app)
```
Aucun processus root, ni dans le groupe root.

```
== Tentative de défiguration du site depuis le conteneur :
$ kubectl -n ssf exec deploy/web -- sh -c 'echo defaced > /usr/share/nginx/html/index.html'
sh: can't create /usr/share/nginx/html/index.html: Read-only file system
command terminated with exit code 1
```
Un attaquant qui obtient un shell dans le conteneur web ne peut ni modifier le site, ni
déposer un outil, ni altérer la configuration nginx.

```
== Ports publiés par le cluster :
$ docker port ssf-dev-control-plane
6443/tcp -> 127.0.0.1:39245
30080/tcp -> 127.0.0.1:8081
30443/tcp -> 127.0.0.1:8444
```
Les trois ports, API Kubernetes comprise, n'écoutent que sur la boucle locale.

### CI

Le job `iac` (GitHub) et un job `chart` (GitLab) rejouent `make chart-lint` : `helm lint
--strict`, rendu avec le tag de `dev.tfvars`, puis trivy sur les manifests rendus (GitHub).
Helm 3.22.0, même branche majeure que la bibliothèque du provider (Helm 3.20).

---

## 3b — le cluster est cloisonné

_(à venir)_

### Pistes déjà notées

- Traefik a une ClusterRole (lecture de tout le cluster). Le restreindre aux namespaces servis.
- Le token de ServiceAccount est encore monté dans les pods web et api : c'est l'« avant » du RBAC.
- Vérifier que kindnet applique les NetworkPolicies (support ajouté dans les versions récentes
  de kind ; la bibliothèque embarquée par le provider est kind 0.31) — une règle ignorée ne
  produit aucune erreur, d'où l'importance de la preuve par le test.
