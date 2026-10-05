# Modèle de menaces — Secure Software Factory

*Jalon 6c — 5 octobre 2026. Relu à chaque changement de la chaîne.*

## Objet et méthode

Ce qu'on protège n'est pas l'application — volontairement triviale ([ADR 0001](adr/0001-application-volontairement-triviale.md)) —
mais **la chaîne** qui la construit, la publie, la déploie et la surveille. La question de fond :
*ce qui tourne dans le cluster est-il exactement ce qui a été contrôlé, et le saurait-on sinon ?*

Méthode : **STRIDE** appliqué élément par élément au schéma des flux (ci-dessous), **cadré par les
cinq ateliers d'EBIOS Risk Manager** (ANSSI) : valeurs métier et événements redoutés, sources de
risque, scénarios stratégiques par l'écosystème, scénarios opérationnels, traitement du risque.
C'est une analyse **allégée**, à l'échelle d'un projet d'une personne : elle suit la démarche
d'EBIOS RM sans en produire tous les livrables (pas de cotation chiffrée de vraisemblance, pas
d'atelier à plusieurs).

Règle de ce document : **chaque contrôle cité renvoie à une preuve exécutable** — une cible
`make` ou un job de CI qui échoue si le contrôle disparaît. Un contrôle sans preuve n'est pas
compté.

## Flux et frontières de confiance

```
  [poste Tunsay]──git push──►[GitHub : dépôt]──►[CI GitHub Actions]──OIDC──►[Sigstore : Fulcio, Rekor]
   WSL2, Docker Desktop            │                 │  contrôles, build, scan, signature
   kubeconfig admin                │                 ▼
   état Terraform du cluster       │            [GHCR : images signées, SBOM attesté]
        │                          │                 │
        │ terraform apply          │ ArgoCD lit      │ tirage par digest
        ▼                          ▼                 ▼
  ┌───────────────────────────── cluster kind ─────────────────────────────────────┐
  │ admission : PSS restricted + Kyverno (signature, registre, digest)   ← frontière│
  │                                                                                 │
  │ argocd ──écrit── ssf : web ──► api        monitoring : Prometheus, Grafana      │
  │                  ▲   (NetworkPolicies deny-by-default)   ▲ lit les métriques    │
  │ ingress : Traefik┘                       security : Kyverno, trivy-operator     │
  └─────────────────────────────────────▲───────────────────────────────────────────┘
                                        │ 127.0.0.1:8081 seulement
                                   [navigateur]
```

Frontières de confiance : le poste (seul détenteur des droits d'administration du cluster), le
dépôt (source de vérité du déploiement), la CI (seule identité autorisée à signer), l'admission du
cluster (dernier point de contrôle avant l'exécution), et le namespace applicatif `ssf`.

## Atelier 1 — Valeurs métier, biens supports, événements redoutés

| Valeur métier | Biens supports | Événement redouté | Gravité |
|---|---|---|---|
| **VM1 — Intégrité de ce qui s'exécute** : ce qui tourne est ce qui a été contrôlé | dépôt, CI, GHCR, Sigstore, admission du cluster, ArgoCD | **ER1** : un code non contrôlé s'exécute dans le cluster | critique |
| **VM2 — Confidentialité des secrets d'infrastructure** | état Terraform du cluster (clé d'administration), kubeconfig, état de la couche platform, jetons de CI | **ER2** : vol de l'identité d'administration du cluster | critique |
| **VM3 — Conformité de l'état déployé** à ce que décrit le dépôt | ArgoCD, Terraform | **ER3** : une modification silencieuse de l'application ou de la plateforme | grave |
| **VM4 — Disponibilité du service** | Traefik, application, Kyverno (`failurePolicy: Fail`) | **ER4** : indisponibilité prolongée | modérée (service de démonstration) |
| **VM5 — Traçabilité** : qui a construit, signé, déployé quoi | historique Git, journal public Rekor, historique ArgoCD, métriques et alertes | **ER5** : une action impossible à attribuer ou à constater | grave |

**Socle de sécurité** (référentiels appliqués, chacun prouvé) : Pod Security Standards
`restricted` (Kubernetes), OWASP Top 10 côté application (SAST, SCA, DAST), principes de SLSA
pour la chaîne d'approvisionnement — provenance par l'identité exacte du workflow signataire et
SBOM attesté, **sans** prétendre à un niveau SLSA certifié (pas d'attestation de provenance SLSA
au sens strict).

## Atelier 2 — Sources de risque et objectifs visés

| Source de risque | Objectif visé | Pertinence |
|---|---|---|
| **SR1 — Attaquant opportuniste** (Internet, robots) | ressources de calcul (minage), rebond, défiguration | moyenne : l'application n'écoute que sur `127.0.0.1`, mais la chaîne publie des images publiques |
| **SR2 — Attaquant de la chaîne d'approvisionnement** (paquet PyPI/npm, image de base, action GitHub, chart Helm compromis) | exécuter du code chez toutes les cibles qui consomment l'artefact | **élevée** : c'est le mode d'attaque dominant contre les chaînes CI/CD |
| **SR3 — Compte compromis** (session GitHub de Tunsay, jeton de CI) | publier ou déployer une version piégée, signée « par nous » | élevée : le dépôt est la source de vérité |
| **SR4 — Attaquant déjà dans un pod** (faille applicative exploitée) | élévation de privilèges, mouvement latéral, vol de secrets, persistance | élevée : c'est l'hypothèse de compromission qui dimensionne le cloisonnement |
| **SR5 — Erreur interne** (opérateur pressé, `kubectl` à la main) | — (non intentionnel) : dérive, panne, exposition accidentelle | élevée : la cause la plus fréquente d'incident réel |

## Atelier 3 — Scénarios stratégiques (par l'écosystème)

| # | Chemin | Événement redouté | Parties prenantes exposées |
|---|---|---|---|
| **SS1** | SR2 pousse une dépendance ou une image de base piégée → elle entre dans le build → l'image est publiée et signée → déployée | ER1 | PyPI, npm, Docker Hub, GHCR |
| **SS2** | SR3 prend la main sur la CI → signe une image malveillante avec notre identité, ou republie un tag | ER1, ER5 | GitHub Actions, Sigstore |
| **SS3** | SR1/SR2 fait tourner dans le cluster une image hors chaîne : autre registre, tag déplacé, image jamais signée | ER1 | GHCR, Docker Hub, admission |
| **SS4** | SR4 exploite l'API → lit un jeton monté → appelle l'API Kubernetes ; ou joint le front, Internet, d'autres namespaces | ER2, ER1 | cluster, réseau |
| **SS5** | SR5 ou SR4 modifie l'application à la main (variable, répliques, Service) → l'écart dure sans que personne ne le voie | ER3, ER4 | ArgoCD, Terraform |
| **SS6** | SR4 ou SR2 compromet un composant de plateforme trop privilégié (outil de déploiement, scanner, Grafana) → hérite de ses droits sur tout le cluster | ER2, ER1 | ArgoCD, trivy-operator, Grafana, Traefik |
| **SS7** | SR1 exploite une faiblesse visible de l'extérieur (en-tête manquant, interface interne exposée, entrée renvoyée) | ER1, ER5 | Traefik, application |

## Atelier 4 — Scénarios opérationnels : STRIDE par élément

S : usurpation d'identité · T : altération · R : répudiation · I : divulgation · D : déni de
service · E : élévation de privilèges.

### Dépôt et poste de développement

| Menace | Scénario | Contrôle | Preuve | Résiduel |
|---|---|---|---|---|
| **I** — secret commité | jeton, clé, mot de passe dans un fichier ou l'historique | gitleaks en pre-commit et en CI, sur les fichiers et l'historique ; règle d'exception étroite | job `gitleaks` ; `make scan` | — |
| **I** — secret laissé sur le disque | état Terraform du cluster (clé d'administration en clair) dans le dossier du projet | état déplacé hors du dépôt, `~/.local/state/ssf`, droits 700 (J4-I6) | `make scan` (gitleaks sur le dossier) | un poste compromis donne tout : **risque accepté**, hors périmètre d'un projet local |
| **T** — dérogation oubliée | une exception de sécurité reste active indéfiniment | dérogations datées ; une dérogation expirée fait échouer la CI | `scripts/check-exceptions.py` en CI | — |

### Chaîne d'approvisionnement et CI

| Menace | Scénario | Contrôle | Preuve | Résiduel |
|---|---|---|---|---|
| **T** — dépendance substituée (SS1) | une version de paquet est remplacée sur l'index | `requirements.txt` à empreintes, `pip --require-hashes` ; `npm ci` sur lockfile | job `api` ; `make supply-chain-proof` (515 empreintes) | une dépendance **légitimement** malveillante dès sa publication passerait — délai de carence Dependabot de 7 jours, PR relues à la main |
| **T** — image de base déplacée (SS1) | le tag `python:3.14-slim` désigne une autre image | 4/4 images de base épinglées par digest | `make supply-chain-proof` | — |
| **E** — dépendance vulnérable | CVE connue dans un paquet ou l'image | pip-audit, npm audit, Trivy bloquant (HIGH/CRITICAL corrigeables) | jobs `api`, `web`, `images` | failles **sans correctif** tolérées au build, mais visibles en continu (trivy-operator, 6b) |
| **T** — action GitHub altérée | un tag d'action est déplacé vers du code malveillant | actions épinglées par SHA ; runners figés `ubuntu-24.04` | revue de `ci.yml` (convention) | images d'outils de CI encore tirées par tag mobile (`semgrep/semgrep`, `bridgecrew/checkov`) : **ouvert** |
| **S** — signature usurpée (SS2) | un autre job, une autre branche ou un fork signe « en notre nom » | signature sans clé, identité **exacte** `ci.yml@refs/heads/main` ; `id-token` réservé au job de publication | `make supply-chain-proof` (identité e2e refusée ; « qui peut signer ») | une prise de contrôle du compte GitHub (SR3) signe légitimement : **risque principal restant** |
| **T** — image publiée ≠ image scannée | reconstruction entre scan et publication | publication de l'image chargée et scannée, vérification de sa configuration | job `images` | — |
| **R** — publication niée | « ce n'est pas nous qui avons publié » | signature et attestation inscrites au journal public Rekor | `cosign verify` en CI | journal public : à remplacer par une instance privée pour un projet privé |

### Admission et exécution dans le cluster

| Menace | Scénario | Contrôle | Preuve | Résiduel |
|---|---|---|---|---|
| **T/S** — image hors chaîne (SS3) | image jamais signée, autre registre, tag au lieu d'un digest | Kyverno en `Deny` : signature **et** SBOM par l'identité de la CI, `ghcr.io/tunsay/` seul, digest obligatoire | `make admission-proof` ; e2e (cluster neuf, Kyverno bloquant dès le départ) | composants de plateforme hors du périmètre de la règle de signature (images épinglées par version de chart) |
| **E** — conteneur privilégié | pod root, `hostPath`, capacités | PSS `restricted` sur **tous** les namespaces, aucune exception | `make infra-proof` ; `make attack-escape` (évasion réussie dans `default`, refusée dans `ssf`) | — |
| **D** — épuisement de ressources | un pod sans limite sature un nœud | quotas et limites par défaut sur chaque namespace | `make infra-proof` | LimitRange sans maximum par conteneur (KSV-0039) : faible, **ouvert** |
| **D** — contrôleur d'admission indisponible | Kyverno en panne ou lent | `failurePolicy: Fail` : « pas pu contrôler » vaut « refusé » | J5-I3 (latence mesurée) | **choix assumé** : la sécurité prime sur la disponibilité ; Kyverno est sur le chemin du déploiement |

### Cloisonnement : réseau et identités (SS4)

| Menace | Scénario | Contrôle | Preuve | Résiduel |
|---|---|---|---|---|
| **E/I** — mouvement latéral | l'API compromise joint le front, Internet, ou un autre namespace la joint | NetworkPolicies deny-by-default, quatre flux ouverts un par un | `make isolation-check` en e2e | **non appliquées sur le poste** (noyau WSL2 sans `NFT_QUEUE`, I8) : prouvées en CI seulement |
| **E** — jeton Kubernetes volé | le pod lit son jeton et appelle l'API Kubernetes | comptes sans jeton (`automountServiceAccountToken: false`) | `make isolation-proof` (tests 6 et 7) | — |
| **I** — composant d'entrée trop privilégié | Traefik lit tous les Secrets du cluster (droit par défaut) | Traefik namespacé | `make isolation-proof` (test 8) | — |

### Déploiement et dérive (SS5, SS6)

| Menace | Scénario | Contrôle | Preuve | Résiduel |
|---|---|---|---|---|
| **T** — modification manuelle | variable, répliques, Service changés à la main | ArgoCD, synchronisation automatique, `selfHeal` | `make drift-check` en e2e (annulée en 9 à 27 s) | un champ **ajouté** ou un objet **étranger** restent : limite mesurée |
| **E** — outil de déploiement compromis | ArgoCD, administrateur du cluster par défaut | aucun droit de cluster ; écrit 4 types d'objets dans `ssf` ; projet borné ; aucun compte | `make drift-check` (droits vérifiés) | — |
| **E/I** — scanner compromis | trivy-operator lit tous les Secrets, crée des Jobs partout (défaut) | droits écrits par nous : lecture de `ssf`, Jobs dans `security` seulement | J6-I2 (journal), rôles dans `trivy.tf` | lecture seule de quelques types cluster (ClusterRole, PV, CRD), exigée par son code |
| **I** — tableau de bord trop privilégié | Grafana lit tous les Secrets du cluster (défaut) | Grafana namespacé, aucun compte, lecture seule | ADR 0015 | Prometheus garde la lecture standard (services, pods) de tout le cluster |
| **R** — déploiement non attribuable | « qui a déployé cette version ? » | déployer = un commit sur `values-dev.yaml` ; `make promote` vérifie signature et SBOM avant d'écrire | historique Git, historique ArgoCD | un seul mainteneur, pas de revue obligatoire : en équipe, protection de branche et CODEOWNERS sur `k8s/` |

### Application vue de l'extérieur (SS7)

| Menace | Scénario | Contrôle | Preuve | Résiduel |
|---|---|---|---|---|
| **T** — injection de script | XSS, script tiers | CSP stricte sans origine externe, sur **toutes** les réponses (piège d'héritage nginx corrigé) | `make dast-check` en e2e (ZAP : 0 avertissement) | — |
| **I** — interfaces internes exposées | métriques, carte OpenAPI, Swagger publics | refusés en bordure (404) ; absents en prod ; métriques lues dans le cluster seulement | `make dast-check` | — |
| **I** — réflexion d'entrée | l'erreur 422 renvoie la valeur reçue | gestionnaire d'erreur sans la valeur ; test unitaire | `make dast-check` ; job `api` | — |
| **S** — usurpation | — | aucune authentification : application de démonstration (ADR 0001) | — | hors périmètre, assumé |
| **I** — trafic en clair | HTTP sans TLS | service lié à `127.0.0.1`, jamais exposé au réseau | `make app-proof` (ports publiés) | pas de TLS : acceptable en local uniquement |

### Détection et traçabilité (VM5)

| Menace | Scénario | Contrôle | Preuve | Résiduel |
|---|---|---|---|---|
| **R** — attaque invisible | refus, dérive, vulnérabilité apparue après le déploiement, sans trace | Prometheus, Grafana « posture sécurité », 6 alertes `famille=securite`, trivy-operator en continu | `make posture-proof` (7/7) ; alerte `SsfRefusAdmission` déclenchée | pas d'Alertmanager : personne n'est prévenu hors du tableau de bord ; rétention 24 h |

## Atelier 5 — Traitement du risque

| Risque résiduel | Décision | En production, on ferait |
|---|---|---|
| Compte GitHub compromis : signe et déploie « légitimement » (SR3) | **accepté** (projet personnel) | double authentification matérielle, protection de branche, revue obligatoire, signatures de commits vérifiées, environnement GitHub protégé pour le job de publication |
| Poste de développement compromis : détient l'administration du cluster | **accepté** (cluster local) | accès au cluster par identité fédérée et éphémère, aucun kubeconfig administrateur persistant |
| NetworkPolicies non appliquées en local | **accepté**, prouvé en CI à chaque changement (ADR 0009) | CNI qui les applique partout (Calico, Cilium) |
| Composants de plateforme hors de la règle de signature | **à traiter** | étendre la vérification aux images de plateforme (signatures des éditeurs), charts par digest |
| Images d'outils de CI par tag mobile | **à traiter** | épinglage par digest, comme les images de base |
| `failurePolicy: Fail` : Kyverno sur le chemin du déploiement (J5-I3) | **accepté** : la sécurité prime | Kyverno à plusieurs répliques, cache de vérification, limiter la règle aux pods si la latence gêne |
| Failles sans correctif dans l'image de l'API (5 hautes) | **accepté**, visible en continu | image de base plus réduite (distroless), reconstruction automatique dès qu'un correctif paraît |
| Pas d'alerte poussée (pas d'Alertmanager) | **accepté** (pas d'astreinte) | Alertmanager vers une messagerie d'astreinte |
| Journal Rekor public | **accepté** (dépôt public) | instance Sigstore privée |

## Comment vérifier ce document

Chaque ligne « Preuve » se rejoue :

```bash
make scan                 # SAST, SCA, Trivy, gitleaks, dérogations
make supply-chain-proof   # signature, SBOM, digests, qui peut signer, build figé
make infra-proof          # PSS : pod root refusé
make attack-escape        # évasion de conteneur : réussie hors durcissement, refusée dans ssf
make isolation-proof      # réseau et identités (verdict strict en CI : isolation-check)
make admission-proof      # Kyverno : quelles images le cluster admet
make drift-proof          # ArgoCD : dérives annulées, droits bornés (strict en CI : drift-check)
make dast                 # ZAP et expositions ciblées (strict en CI : dast-check)
make posture-proof        # ce que la chaîne a refusé, réparé, trouvé
```

Et le workflow `e2e` rejoue les preuves bloquantes sur un cluster construit de zéro, à chaque
changement d'infrastructure et chaque lundi.
