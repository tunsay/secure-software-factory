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
