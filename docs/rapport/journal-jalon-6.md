# Journal de bord — jalon 6

Notes prises au fil de l'eau, matière première du chapitre `06-jalon-6.md`. Chaque incident :
symptôme, cause, diagnostic, correction, leçon. Chaque livrable : avant / après, et de quoi on
est protégé.

Objectif : passer de la prévention à la **vérification de l'application qui tourne** et à la
**détection**, puis raconter le tout.

- **6a — DAST** : ZAP analyse l'application telle qu'un visiteur la voit ; on corrige ce qu'il
  trouve, et la CI l'exige ensuite à chaque changement.
- **6b — observabilité** : Prometheus + Grafana, tableau de bord « posture sécurité ».
- **6c — modèle de menaces** STRIDE, relié à EBIOS RM.
- **6d — vitrine** : README final, schéma, GitHub Pages, PDF du rapport.

---

## 6a — vérifications faites avant d'écrire (04/10)

| # | Constat | Conséquence |
|---|---|---|
| V1 | ZAP **2.17.0** (15/12/2025) est la dernière version stable ; depuis, uniquement des versions hebdomadaires. Image `ghcr.io/zaproxy/zaproxy:2.17.0` = même digest que `stable` (`sha256:781a2bda…`). | Image épinglée par digest, comme toutes les autres. |
| V2 | Scan **« baseline »** : exploration du site, puis analyse **passive** de chaque réponse. Rien n'est attaqué. | Lançable sur n'importe quel environnement, y compris en CI à chaque changement. |
| V3 | ZAP lancé dans le réseau Docker de kind (`--network kind`), cible `http://ssf-dev-control-plane:30080` : le NodePort de Traefik, même chemin que `127.0.0.1:8081` sur le poste. | Même commande en local et sur le runner e2e. |
| V4 | Ce que ZAP ne trouvera pas seul (aucune page n'y mène) : `/api/metrics`, `/api/openapi.json`, `/api/docs`, et l'écho de l'entrée dans les erreurs de validation — dettes notées au jalon 1. | Quatre tests ciblés ajoutés à la même commande, `make dast`. |

## AVANT 6a — `make dast` (04/10)

Partie ZAP (sortie condensée : les 62 lignes `PASS` sont omises) :

```
Total of 6 URLs
WARN-NEW: X-Content-Type-Options Header Missing [10021] x 2
        http://ssf-dev-control-plane:30080/assets/index-BQM4aTYW.css (200 OK)
        http://ssf-dev-control-plane:30080/assets/index-ZC_0jv4X.js (200 OK)
WARN-NEW: Storable and Cacheable Content [10049] x 5
        http://ssf-dev-control-plane:30080 (200 OK)
        http://ssf-dev-control-plane:30080/assets/index-BQM4aTYW.css (200 OK)
        http://ssf-dev-control-plane:30080/assets/index-ZC_0jv4X.js (200 OK)
        http://ssf-dev-control-plane:30080/robots.txt (200 OK)
        http://ssf-dev-control-plane:30080/sitemap.xml (200 OK)
WARN-NEW: Permissions Policy Header Not Set [10063] x 1
        http://ssf-dev-control-plane:30080/assets/index-ZC_0jv4X.js (200 OK)
WARN-NEW: Modern Web Application [10109] x 3
        http://ssf-dev-control-plane:30080 (200 OK)
        http://ssf-dev-control-plane:30080/robots.txt (200 OK)
        http://ssf-dev-control-plane:30080/sitemap.xml (200 OK)
WARN-NEW: Cross-Origin-Embedder-Policy Header Missing or Invalid [90004] x 10
        http://ssf-dev-control-plane:30080 (200 OK)
        http://ssf-dev-control-plane:30080/robots.txt (200 OK)
        http://ssf-dev-control-plane:30080/sitemap.xml (200 OK)
        http://ssf-dev-control-plane:30080 (200 OK)
        http://ssf-dev-control-plane:30080/robots.txt (200 OK)
FAIL-NEW: 0     FAIL-INPROG: 0  WARN-NEW: 5     WARN-INPROG: 0  INFO: 0 IGNORE: 0       PASS: 62
```

Partie ciblée :

```
EXPOSÉ   métriques internes de l'API (Prometheus)   — /api/metrics → HTTP 200
EXPOSÉ   description complète de l'API (OpenAPI)    — /api/openapi.json → HTTP 200
EXPOSÉ   interface Swagger de l'API                 — /api/docs → HTTP 200
EXPOSÉ   erreur de validation : l'entrée est renvoyée telle quelle
         réponse : {"detail":[{"type":"int_parsing","loc":["body","quantity"],"msg":"Input should be a valid integer, unable to parse string as an integer","input":"<script>alert(1)</script>"}]}
```

Lecture :

- **Les en-têtes de sécurité disparaissent sur les fichiers JS et CSS** (10021, 10063).
  Hypothèse formulée avant le scan, confirmée : dans `nginx.conf`, le bloc des fichiers
  statiques déclare son propre `add_header Cache-Control` ; or nginx n'hérite des `add_header`
  du niveau supérieur **que si le bloc n'en déclare aucun**. Un seul en-tête ajouté dans un bloc
  supprime donc, pour ce bloc, la CSP, `nosniff`, `X-Frame-Options`... Même défaut sur
  `/healthz`. Aucun outil statique ne l'avait vu : il n'apparaît qu'à l'exécution.
- **Isolation entre origines jamais configurée** (90004) : ni `Cross-Origin-Embedder-Policy`,
  ni `-Opener-Policy`, ni `-Resource-Policy`.
- **Toute adresse inconnue répond 200** avec la page d'accueil (`robots.txt`, `sitemap.xml`) :
  le repli des applications à routage côté client, inutile ici (une seule page, aucune route).
- 10049 (contenu stockable en cache) et 10109 (« application web moderne ») sont des
  **informations**, pas des failles : contenu public et statique, dont la mise en cache est
  voulue ; et une application d'une page dont les appels d'API sont testés à part.
- **Les quatre expositions ciblées sont ouvertes** : n'importe qui lit les métriques internes
  de l'API et la carte complète de ses routes, et l'API renvoie au client ce qu'il a envoyé — ici
  un `<script>`. Réponse en JSON, donc pas exécutable en l'état, mais c'est une réflexion
  d'entrée : le premier maillon d'une injection, le jour où un client affiche ce message.

## 6a — corrections (commit `12fa353`) et déploiement (commit `1bd80f0`)

| Constat | Correction |
|---|---|
| En-têtes de sécurité absents sur JS et CSS (héritage nginx) | en-têtes regroupés dans `app/web/security-headers.conf`, **inclus dans chaque bloc** qui déclare ses propres `add_header` ; `/healthz` passe par `default_type` au lieu d'un `add_header` |
| Isolation entre origines absente (90004) | `Cross-Origin-Opener-Policy`, `-Embedder-Policy`, `-Resource-Policy` |
| Toute adresse inconnue répond 200 | `try_files … =404` : une page, aucune route côté client |
| `/api/metrics`, `/api/openapi.json`, `/api/docs` publics | refusés par nginx en bordure (404) ; en prod, FastAPI ne crée ni `/docs` ni `/openapi.json`. Prometheus lira les métriques dans le cluster (6b) |
| L'erreur 422 renvoie l'entrée | gestionnaire d'erreur qui garde le champ et la raison, jamais la valeur ; test unitaire ajouté |
| 10049, 10109 (informations) | `IGNORE` dans `security/zap-rules.tsv`, dérogations datées dans `security/exceptions.yaml` |

- `make test && make scan` : un premier échec de `ruff format` (une ligne vide manquante après la
  nouvelle fonction) a bloqué le commit avant qu'il existe — shift-left ; puis tout vert.
- **`make promote SHA=<sha>`** (nouveau) : récupère les digests d'un commit dans le registre,
  vérifie signature **et** SBOM avec la même règle que Kyverno, puis seulement écrit
  `values-dev.yaml`. Il ne commite rien : déployer reste un geste humain. Sortie réelle :
  `ssf-api : sha256:3b9c0754… — signature et SBOM vérifiés`, `ssf-web : sha256:4b874a07… —
  signature et SBOM vérifiés`.
- Commit `1bd80f0` : déploiement de 12fa353, et `make dast-check` ajouté au workflow e2e
  (bloquant). ArgoCD a déployé **exactement** cette révision : `Synced/Healthy — révision
  déployée 1bd80f0, attendue 1bd80f0`.

## APRÈS 6a — `make dast` (04/10, révision 1bd80f0 déployée par ArgoCD)

Partie ZAP (sortie condensée : les 65 lignes `PASS` sont omises, sauf les trois qui étaient des
avertissements avant) :

```
Total of 6 URLs
PASS: X-Content-Type-Options Header Missing [10021]
PASS: Permissions Policy Header Not Set [10063]
PASS: Insufficient Site Isolation Against Spectre Vulnerability [90004]
IGNORE: Storable and Cacheable Content [10049] x 4
        http://ssf-dev-control-plane:30080 (200 OK)
        http://ssf-dev-control-plane:30080/assets/index-BQM4aTYW.css (200 OK)
        http://ssf-dev-control-plane:30080/assets/index-ZC_0jv4X.js (200 OK)
        http://ssf-dev-control-plane:30080/sitemap.xml (404 Not Found)
IGNORE: Modern Web Application [10109] x 1
        http://ssf-dev-control-plane:30080 (200 OK)
FAIL-NEW: 0     FAIL-INPROG: 0  WARN-NEW: 0     WARN-INPROG: 0  INFO: 0 IGNORE: 2       PASS: 65
```

Partie ciblée :

```
FERMÉ    métriques internes de l'API (Prometheus)   — /api/metrics → HTTP 404
FERMÉ    description complète de l'API (OpenAPI)    — /api/openapi.json → HTTP 404
FERMÉ    interface Swagger de l'API                 — /api/docs → HTTP 404
FERMÉ    erreur de validation : l'entrée n'est pas renvoyée
         réponse : {"detail":[{"type":"int_parsing","loc":["body","quantity"],"msg":"Input should be a valid integer, unable to parse string as an integer"}]}
```

| | Avant | Après |
|---|---|---|
| Avertissements ZAP | **5** | **0** |
| Contrôles ZAP réussis | 62 | **65** |
| Dérogations ZAP | 0 | 2, justifiées et datées |
| `/api/metrics`, `/api/openapi.json`, `/api/docs` | **publics** (200) | **fermés** (404) |
| Erreur de validation | **renvoie l'entrée** (`<script>`) | champ et raison, sans la valeur |
| Adresse inconnue | 200, page d'accueil | 404 |

- **En CI** : le workflow e2e de `1bd80f0` est vert, avec `make dast-check` **bloquant** sur un
  cluster neuf (ArgoCD, Kyverno en `Deny`). Toute régression — un en-tête perdu, une interface
  interne republiée, un écho d'entrée — fait désormais échouer la CI.
- Les noms des fichiers JS et CSS n'ont pas changé (`index-BQM4aTYW.css`, `index-ZC_0jv4X.js`) :
  le code du front est identique, seule la configuration nginx a changé. Le défaut n'était pas
  dans le code de l'application mais dans la façon de la servir.

## AVANT 6b — `make posture-proof` (04/10)

Sept questions qu'un responsable sécurité se pose chaque matin, posées à Prometheus par l'API
Kubernetes (aucun port ouvert) :

```
== Aucun Prometheus dans le cluster

== 1. Requêtes refusées à l'admission par Kyverno, dernière heure
   SANS RÉPONSE  aucune mesure collectée

== 2. L'application est-elle synchronisée avec le dépôt, et saine ?
   SANS RÉPONSE  aucune mesure collectée

== 3. Vulnérabilités dans les images qui tournent dans ssf, par gravité
   SANS RÉPONSE  aucune mesure collectée

== 4. Défauts de configuration des workloads de ssf, par gravité
   SANS RÉPONSE  aucune mesure collectée

== 5. Redémarrages de conteneurs dans ssf, dernière heure
   SANS RÉPONSE  aucune mesure collectée

== 6. Réponses d'erreur (5xx) servies au public par Traefik, dernière heure
   SANS RÉPONSE  aucune mesure collectée

== 7. Alertes de sécurité en cours
   SANS RÉPONSE  aucune mesure collectée
```

Lecture : tous les contrôles des jalons 1 à 6a **empêchent**, aucun ne **raconte**. Un refus
Kyverno, une dérive annulée par ArgoCD, une vulnérabilité publiée après le déploiement : rien de
tout cela ne laisse de trace consultable. Au jalon 5, l'application est restée en panne sans que
rien ne le signale (J5-I3).

## 6b — vérifications faites avant d'écrire (04/10)

| # | Constat | Conséquence |
|---|---|---|
| V5 | `kube-prometheus-stack` : une version tous les un à deux jours. **91.7.1** (27/09) est la plus récente de plus de 7 jours : prometheus-operator v0.94.1, Grafana (chart 13.2.6), kube-state-metrics (chart 8.6.0). | Chart 91.7.1 épinglé. |
| V6 | Le chart installe aussi **node-exporter** : pod avec `hostNetwork`, `hostPID` et montages du nœud, interdit par PSS restricted (et par notre module de namespace, qui refuse `privileged`). | node-exporter désactivé : la posture de sécurité n'a pas besoin des métriques du système des nœuds. Même raison que l'abandon de kube-bench. |
| V7 | trivy-operator **v0.34.0** (24/08), chart 0.36.0 : scanne en continu les images qui tournent et la configuration des workloads, expose des métriques Prometheus. | Couvre la question 3 : une vulnérabilité publiée **après** le déploiement, que la CI ne voit plus. |
| V8 | trivy-operator, droits par défaut (ClusterRole du chart, lue dans le template) : lecture de **tous les Secrets** du cluster (`accessGlobalSecretsAndServiceAccount: true`), **création de Jobs dans tous les namespaces**, lecture de toutes les ConfigMaps et de tous les journaux de pods. | Un scanner de sécurité compromis pourrait lancer un pod privilégié dans un namespace non durci : chemin d'escalade. Même problème que le chart d'ArgoCD au 5b. |

## Incidents

### J6-I1 — L'attente échoue sur un pod qui disparaît pendant qu'on l'attend

- **Symptôme** : après le déploiement de 1bd80f0, ArgoCD rapporte `Synced/Healthy`, les trois
  nouveaux pods sont prêts (`condition met`), puis `make app-wait` échoue : `Error from server
  (NotFound): pods "web-657f574c9f-29nc6" not found`. La chaîne s'arrête avant `make dast`.
- **Cause** : `kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=ssf` liste les
  pods par étiquette **au départ**, anciens compris. Un ancien pod `web`, en cours d'arrêt à ce
  moment-là, a disparu pendant l'attente : `kubectl wait` échoue sur un objet qui n'existe plus.
  L'application, elle, était saine.
- **Correction** : attendre les **Deployments** (`condition=Available`), qui ne disparaissent pas
  pendant un déploiement. « Healthy » pour ArgoCD garantit déjà que la nouvelle version est
  entièrement prête.
- **Leçon** : pendant un changement, attendre un objet stable, pas des objets éphémères. Même
  famille que J5-I2 : une attente doit viser l'état qu'on veut constater.
