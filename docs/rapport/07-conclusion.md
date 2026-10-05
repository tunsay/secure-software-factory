# Chapitre 7 — Conclusion : une chaîne, pas une collection d'outils

*5 octobre 2026*

## Comment les six jalons s'emboîtent

Aucun jalon n'est isolé : chacun s'appuie sur les précédents, et plusieurs n'auraient **aucun
sens** sans eux. Kyverno (jalon 5) ne vérifie rien si les images ne sont pas signées (jalon 4) ;
la signature ne vaut rien si l'image signée n'est pas celle qui a été scannée (jalons 1 et 4) ;
le tableau de bord (jalon 6) n'affiche que ce que les autres jalons produisent.

```
 J1  CONTRÔLER  ─────────►  J4  PUBLIER CE QUI A ÉTÉ CONTRÔLÉ  ─────────►  J5  N'ADMETTRE QUE
     SAST, SCA, Trivy,           image scannée, signée,                        CE QUI EST SIGNÉ
     gitleaks                    SBOM, digest                                  (Kyverno)
        │                                                                          │
        │ dettes notées (docs, métriques, 422)                                     │ refus comptés
        ▼                                                                          ▼
 J2  TERRAIN DURCI  ─────►  J3  DÉPLOYER CLOISONNÉ  ─────►  J5  ÉTAT = DÉPÔT  ─►  J6  VOIR ET
     Terraform, PSS,            Traefik, NetworkPolicies,       (ArgoCD, sans         TESTER
     OIDC sans secret           comptes sans jeton,             droits de cluster)    ZAP, Prometheus,
                                workflow e2e  ──── réutilisé par J5 et J6 ────►       trivy-operator,
                                                                                      menaces
```

| Jalon | S'appuie sur… | Et rend possible… |
|---|---|---|
| **1** — contrôler le code | — | la règle de toute la chaîne : rien ne part sans contrôle ; des dettes notées, soldées au jalon 6 |
| **2** — Terraform pilote le cluster | les contrôles du 1, étendus à l'IaC | le terrain : namespaces durcis où tout le reste s'installe ; le zéro secret (OIDC) qui permet la signature sans clé du 4 |
| **3** — déployer et cloisonner | les namespaces du 2 | une application qui tourne, cloisonnée ; le workflow e2e, réutilisé pour prouver les jalons 5 et 6 |
| **4** — chaîne d'approvisionnement | le pipeline du 1, le registre OIDC du 2 | des images **vérifiables** : sans signature ni digest, l'admission du 5 n'aurait rien à vérifier |
| **5** — policy as code et GitOps | les signatures du 4, les namespaces du 2, les NetworkPolicies du 3 (laissées à Terraform pour qu'ArgoCD ne puisse pas les élargir) | un cluster qui refuse seul et revient seul à l'état du dépôt |
| **6** — DAST, observabilité, menaces | tout le reste : ZAP teste ce qu'ArgoCD a déployé ; Prometheus compte les refus de Kyverno et les dérives d'ArgoCD ; le modèle de menaces relie chaque contrôle à sa preuve | la vue d'ensemble, et le récit |

Les « ateliers » du [modèle de menaces](../threat-model.md) sont ceux d'EBIOS RM : ils ne
correspondent pas aux jalons, ils les **relient**. Chaque menace identifiée y renvoie au jalon qui
la traite et à la commande qui le prouve.

## De quoi on est protégé — tableau de synthèse

Chaque ligne est prouvée par une commande `make` ou un job de CI qui échoue si le contrôle
disparaît. Entre parenthèses, le jalon qui a complété ou corrigé le contrôle.

### Code et dépendances

| On est protégé contre… | Technologie installée | Jalon | Prouvé par |
|---|---|---|---|
| un secret commité (clé, jeton, mot de passe), dans un fichier ou l'historique | gitleaks, en pre-commit et en CI | 1 | job `gitleaks`, `make scan` |
| du code dangereux (injection, appel risqué, erreur de type) | ruff, bandit, semgrep, eslint-plugin-security, tsc | 1 | jobs `api`, `web`, `semgrep` |
| une dépendance vulnérable | pip-audit, npm audit, Dependabot (délai de 7 jours) | 1 | jobs `api`, `web` |
| un paquet Python substitué sur l'index | pip-tools (empreintes), `pip --require-hashes` | 4 | `make supply-chain-proof` |
| une dérogation de sécurité oubliée | dérogations datées, `check-exceptions.py` | 4 | job `gitleaks`, `make scan` |

### Build et images

| On est protégé contre… | Technologie installée | Jalon | Prouvé par |
|---|---|---|---|
| une image avec une faille corrigeable (HIGH, CRITICAL) | Trivy, bloquant | 1 | job `images` |
| un conteneur trop permissif (root, écriture, capacités) | images multi-stage non-root, nginx non privilégié, lecture seule | 1 (3) | `make app-proof` |
| une image de base déplacée sous son tag | images de base épinglées par digest | 4 | `make supply-chain-proof` |
| une image publiée malgré un contrôle rouge | publication conditionnée à tous les jobs | 3 | CI |
| une image publiée différente de celle scannée | publication de l'image chargée et scannée | 4 | job `images` |
| une image d'origine inconnue, une signature usurpée | Cosign sans clé (Sigstore), identité exacte du workflow | 4 | `make supply-chain-proof` |
| un contenu non inventorié | SBOM CycloneDX (Syft), attesté et signé | 4 | `make supply-chain-proof` |
| un job de CI compromis qui signerait en notre nom | permissions CI au moindre privilège | 4 | `make supply-chain-proof` |
| une action GitHub ou une machine de CI modifiée | actions épinglées par SHA (jalon 1), runners figés `ubuntu-24.04` (début du jalon 4) | 1, 4 | convention, revue |

### Infrastructure

| On est protégé contre… | Technologie installée | Jalon | Prouvé par |
|---|---|---|---|
| une infrastructure mal configurée | Terraform, Checkov, trivy config | 2 | job `iac`, `make infra-lint` |
| une clé d'accès statique volée dans la CI | OIDC GitHub vers GHCR : aucun secret | 2 | configuration de la CI |
| la clé d'administration du cluster laissée dans le projet | état Terraform du cluster hors du dépôt | 4 | `make scan` (gitleaks) |
| des manifests Kubernetes dangereux | helm lint, Trivy sur le chart rendu | 3 | `make chart-lint`, CI |

### Admission dans le cluster

| On est protégé contre… | Technologie installée | Jalon | Prouvé par |
|---|---|---|---|
| un pod root, privilégié, ou une évasion vers le nœud (`hostPath`) | Pod Security Standards `restricted` | 2 | `make infra-proof`, `make attack-escape` |
| une image non signée par notre CI, même conforme à PSS | Kyverno, `ImageValidatingPolicy` (signature et SBOM) | 5 | `make admission-proof`, e2e |
| une image d'un autre registre, ou désignée par un tag | Kyverno, `ValidatingPolicy` ; chart qui exige un digest | 4, 5 | `make admission-proof` |
| un épuisement des ressources du nœud | ResourceQuota, LimitRange | 2 | `make infra-proof` |

### Réseau et identités

| On est protégé contre… | Technologie installée | Jalon | Prouvé par |
|---|---|---|---|
| un mouvement latéral, une exfiltration vers Internet | NetworkPolicies deny-by-default | 3 | `make isolation-check` (e2e) |
| le vol du jeton Kubernetes depuis un pod | comptes de service sans jeton | 3 | `make isolation-proof` |
| un ingress qui lirait tous les Secrets du cluster | Traefik aux droits namespacés | 3 | `make isolation-proof` |
| une exposition au réseau local | ports du cluster publiés sur `127.0.0.1` seulement (Traefik en NodePort) | 2, 3 | `make app-proof` |

### Déploiement

| On est protégé contre… | Technologie installée | Jalon | Prouvé par |
|---|---|---|---|
| une modification manuelle de l'application (dérive) | Argo CD, synchronisation automatique et `selfHeal` | 5 | `make drift-check` (e2e) |
| un outil de déploiement compromis | Argo CD sans droits de cluster, projet borné, aucun compte | 5 | `make drift-check` (droits) |
| le déploiement d'une image non vérifiée | `make promote` : signature et SBOM vérifiés avant d'écrire | 6 | journal du jalon 6 |

### Application vue de l'extérieur

| On est protégé contre… | Technologie installée | Jalon | Prouvé par |
|---|---|---|---|
| un script injecté (XSS), un script tiers | CSP stricte et en-têtes de sécurité sur **toutes** les réponses | 1 (6) | `make dast-check` (e2e) |
| des interfaces internes exposées (métriques, OpenAPI, Swagger) | nginx les refuse ; absentes en prod | 6 | `make dast-check` |
| une réflexion d'entrée dans les erreurs | gestionnaire d'erreur FastAPI sans la valeur reçue | 6 | `make dast-check`, test unitaire |
| une faille visible seulement à l'exécution | OWASP ZAP, bloquant | 6 | `make dast-check` (e2e) |

### Détection

| On est protégé contre… | Technologie installée | Jalon | Prouvé par |
|---|---|---|---|
| une faille publiée **après** le déploiement | trivy-operator (droits écrits par nous), alerte sur faille critique | 6 | `make posture-proof` |
| un refus, une dérive, une panne passés inaperçus | Prometheus, Grafana, 6 alertes de sécurité | 6 | `make posture-proof` |
| des outils d'exploitation trop privilégiés (lecture de tous les Secrets) | Grafana namespacé, trivy-operator aux droits restreints | 6 | ADR 0015, incident J6-I2 |

## Ce qui n'est pas couvert

Dit tel quel dans le [modèle de menaces](../threat-model.md) (atelier 5). Les trois premiers :

- **le compte GitHub** : qui le contrôle signe et déploie « légitimement » — point de défaillance
  unique, accepté pour un projet personnel ;
- **le poste de développement**, qui détient l'administration du cluster ;
- **les composants de plateforme** (Traefik, Kyverno, ArgoCD, Prometheus), hors de la règle de
  signature, installés par version de chart et non par digest.

## Ce que le projet démontre

Une sécurité **par couches**, où chaque couche suppose que la précédente peut échouer : si une
dépendance piégée passe les scanners, l'image n'est publiée que signée et inventoriée ; si une
image non signée est poussée, le cluster la refuse ; si un pod est compromis, il ne joint rien et
ne détient aucun jeton ; si quelqu'un modifie l'application à la main, ArgoCD la remet en état ; et
tout cela se voit sur un tableau de bord.

Et une **méthode** : vérifier avant d'écrire, mesurer avant et après, garder chaque incident avec
sa leçon. Les erreurs du projet — une prémisse fausse rattrapée par la mesure, des droits par
défaut trop larges découverts dans le code des charts, des vérifications qui se trompaient
elles-mêmes — sont dans le rapport, parce que c'est là que se trouve l'apprentissage.
