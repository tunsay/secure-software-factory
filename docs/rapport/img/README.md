# Captures d'écran du rapport

Déposer ici les PNG nommés exactement comme ci-dessous. Le rapport les référence par ce nom.

## Jalon 1

| Fichier | Quoi | Où |
|---|---|---|
| `01-app.png` | La page sur http://localhost:8080 avec « API : ok · v0.1.0 · local » et un item ajouté | navigateur |
| `01-ci-verte.png` | Le run `ci` avec les six jobs verts | github.com/tunsay/secure-software-factory/actions → dernier run |
| `01-ci-rouge.png` | Le tout premier run, semgrep et Trivy en rouge | même page, run le plus ancien |
| `01-security-alerts.png` | Onglet Security → Code scanning, filtre `is:closed` | github.com/tunsay/secure-software-factory/security/code-scanning?query=is%3Aclosed |
| `01-dependabot.png` | Onglet Pull requests, filtre `is:closed`, les deux PR refusées | github.com/tunsay/secure-software-factory/pulls?q=is%3Aclosed |

## Jalon 2

| Fichier | Quoi | Où |
|---|---|---|
| `02-docker-containers.png` | Les trois nœuds `ssf-dev-*` en cours d'exécution, port 8444 publié | Docker Desktop → Containers |
| `02-docker-images.png` | `kindest/node` tirée par digest (tag `<none>`), 1,35 Go | Docker Desktop → Images |
| `02-docker-volumes.png` | Les trois volumes `/var` des nœuds, dont celui d'etcd | Docker Desktop → Volumes |

Conseils : fenêtre du navigateur à ~1400 px de large, thème clair (meilleur rendu à l'impression),
Win+Maj+S pour capturer une zone.
