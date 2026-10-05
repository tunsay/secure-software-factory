# Lancer le projet de zéro sur un nouveau PC

Guide pas à pas : d'un Windows neuf à l'application qui tourne dans son cluster, avec Kyverno,
ArgoCD, Prometheus et Grafana.

- **Durée** : environ 45 minutes la première fois (installations et téléchargements), puis
  10 minutes pour chaque reconstruction.
- **Aucun compte cloud, aucun secret** : tout tourne sur le poste, et les images de l'application
  sont publiques sur GHCR, déjà signées.

Toutes les commandes `bash` se lancent dans le terminal **Ubuntu (WSL)**, sauf mention
contraire.

---

## 0. Ce qu'il faut

| Élément | Minimum |
|---|---|
| Système | Windows 10 (22H2) ou 11, 64 bits, virtualisation activée dans le BIOS (exigée par WSL2) |
| Mémoire | 16 Go conseillés : le cluster complet, surveillance comprise, en utilise plusieurs Go |
| Disque | environ 40 Go libres (images, nœuds du cluster, cache de construction) |
| Ports | `8081` et `8444` libres sur `127.0.0.1` |

## 1. Installer WSL2 et Ubuntu 22.04

Dans **PowerShell, en administrateur** :

```powershell
wsl --install -d Ubuntu-22.04
```

Redémarre si Windows le demande, puis ouvre « Ubuntu 22.04 » et crée ton utilisateur.

## 2. Activer cgroup v2 — obligatoire

Kubernetes (depuis la version 1.31) refuse de démarrer en cgroup v1, le mode par défaut de WSL2
(chapitre 2, incident 1). Crée le fichier `C:\Users\<ton utilisateur>\.wslconfig` :

```ini
[wsl2]
kernelCommandLine = cgroup_no_v1=all systemd.unified_cgroup_hierarchy=1
```

Puis, dans PowerShell : `wsl --shutdown`. Rouvre Ubuntu et vérifie :

```bash
stat -fc %T /sys/fs/cgroup
```

Réponse attendue : `cgroup2fs`.

## 3. Installer Docker Desktop

Installe Docker Desktop pour Windows, puis **Settings → Resources → WSL integration** : active
**Ubuntu-22.04**. Vérifie dans Ubuntu :

```bash
docker version
```

## 4. Récupérer le code

Dans le dossier personnel de WSL (`~`), **pas** sous `/mnt/c` : c'est plus rapide, et on évite
les conflits de verrou entre le git de Windows et celui de WSL (chapitre 3, incident 10).

```bash
cd ~ && git clone https://github.com/tunsay/secure-software-factory.git && cd secure-software-factory
```

*Si tu clones malgré tout sous `/mnt/c` :
`git config core.trustctime false && git config core.checkStat minimal`.*

## 5. Installer les outils

Une seule commande installe Terraform, kubectl, kind, Helm, Trivy, gitleaks, Syft, cosign,
pre-commit, et `make`. Ubuntu neuf n'a pas `make` : on lance donc le script directement.

```bash
bash scripts/install-tools.sh && source ~/.bashrc
```

Le récapitulatif final doit afficher une version pour chaque outil, `docker` compris. Si
`docker` est `ABSENT`, reviens à l'étape 3 (intégration WSL).

## 6. Lancer le projet

**6.1 — Télécharger l'image des nœuds du cluster.** Docker dans WSL refuse parfois de télécharger
les images publiques (`error getting credentials`) ; une configuration Docker vide contourne le
problème.

```bash
DOCKER_CONFIG=$(mktemp -d) docker pull kindest/node:v1.35.0@sha256:452d707d4862f52530247495d180205e029056831160e22870e37e3f6c1ac31f
```

**6.2 — Tout construire.**

```bash
make infra-up
```

Ce que fait cette commande, en une dizaine de minutes :

1. Terraform crée le **cluster** kind (1 control-plane, 2 workers) ;
2. Terraform installe la **plateforme** : namespaces durcis, Traefik, NetworkPolicies, Kyverno,
   ArgoCD, Prometheus, Grafana, trivy-operator ;
3. **ArgoCD** déploie l'application depuis GitHub (version décrite dans
   `k8s/chart/values-dev.yaml`), et la commande attend qu'elle soit prête.

Terraform demande **deux fois `yes`** : relis d'abord le plan, il ne doit annoncer que des
ajouts (`0 to destroy`).

**6.3 — Vérifier.**

```bash
make app-proof
```

L'application répond sur **http://127.0.0.1:8081**.

## 7. Démontrer les contrôles

| Commande | Ce qu'elle montre |
|---|---|
| `make admission-proof` | Kyverno n'admet que les images signées par la CI, de `ghcr.io/tunsay`, par digest |
| `make drift-proof` | ArgoCD annule une modification manuelle de l'application |
| `make dast` | ZAP et quatre tests ciblés : l'application vue de l'extérieur |
| `make posture-proof` | sept questions de sécurité posées à Prometheus (la première fois, il attend jusqu'à 6 minutes les scans de trivy-operator) |
| `make isolation-proof` | cloisonnement réseau et identités |
| `make supply-chain-proof` | signature, SBOM, digest, qui peut signer |
| `make attack-escape` | une évasion de conteneur, réussie hors durcissement, refusée dans `ssf` |
| `make infra-proof` | un pod root refusé à l'admission |

## 8. Ouvrir Grafana, Prometheus et ArgoCD

Ces interfaces ne sont pas exposées (choix de sécurité, ADR 0014 et 0015) : on les ouvre par
port-forward, ce qui exige les droits d'administration du cluster.

```bash
K="kubectl --kubeconfig $HOME/.kube/ssf-dev --context kind-ssf-dev"; ($K -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80 >/dev/null 2>&1 &); ($K -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090 >/dev/null 2>&1 &); ($K -n argocd port-forward svc/argocd-server 8090:443 >/dev/null 2>&1 &); sleep 3; echo "Grafana : http://127.0.0.1:3000/d/ssf-posture | Prometheus : http://127.0.0.1:9090/alerts | ArgoCD : https://127.0.0.1:8090"
```

| Interface | Adresse | Accès |
|---|---|---|
| Grafana, tableau de bord « Posture sécurité » | http://127.0.0.1:3000/d/ssf-posture | lecture seule, sans compte |
| Prometheus, alertes de sécurité | http://127.0.0.1:9090/alerts | lecture |
| ArgoCD | https://127.0.0.1:8090 | lecture seule, sans compte ; certificat auto-signé (avertissement du navigateur normal) |

Pour les refermer : `pkill -f "kubectl.*port-forward"`.

## 9. Pour modifier le code (facultatif)

```bash
# Node.js 24 (LTS), pour l'outillage du front
curl -fsSL https://deb.nodesource.com/setup_24.x -o /tmp/nodesource_setup.sh && sudo -E bash /tmp/nodesource_setup.sh && sudo apt-get install -y nodejs

make setup                                                            # outils Python et npm du projet
pre-commit install --hook-type pre-commit --hook-type commit-msg     # contrôles avant chaque commit
make scan                                                             # rejoue les contrôles de la CI
```

## 10. Arrêter et détruire

```bash
make infra-down
```

Détruit la plateforme, puis le cluster (deux confirmations). Pour faire de la place ensuite :
`docker system df` montre ce que Docker occupe ; les images du projet peuvent être supprimées
avec `docker rmi`.

## 11. Problèmes connus

| Symptôme | Cause | Solution |
|---|---|---|
| `error getting credentials` au téléchargement d'une image | assistant d'identifiants de Docker Desktop, vu depuis WSL | `DOCKER_CONFIG=$(mktemp -d) docker pull <image>` |
| `kubeadm init … exit status 1` à la création du cluster | cgroup v1 | étape 2, puis `wsl --shutdown` |
| port `8081` déjà utilisé | un autre service l'occupe | le libérer : c'est le port que supposent les preuves (sinon : variable `ingress_http_port` de `infra/terraform/cluster`, et adapter `app-proof` et `dast`) |
| après un redémarrage de Docker Desktop, plus de cluster | un cluster kind est jetable | `make infra-up` le reconstruit |
| `make infra-up` échoue au plan : cluster introuvable | l'état Terraform décrit un cluster qui n'existe plus | `cd infra/terraform/cluster && terraform state rm kind_cluster.this && cd -`, puis `make infra-up` |
| `make isolation-check` échoue sur les tests réseau | le noyau WSL2 n'a pas `NFT_QUEUE` : les NetworkPolicies ne s'appliquent pas en local (chapitre 3, incident 8) | attendu ; la preuve réseau se fait en CI (workflow e2e) |
| `fatal: Unable to create '.git/index.lock'` | dépôt sous `/mnt/c`, partagé avec le git de Windows | cloner dans `~` (étape 4) |

**Sécurité** : ne partage jamais la sortie d'un plan Terraform qui **remplace ou détruit** le
cluster. Le fournisseur kind y affiche la clé privée d'administration (chapitre 3, incident 2).
Une clé de cluster détruit est sans valeur, mais la règle évite l'erreur le jour où il existe.

## 12. Sur un autre compte GitHub (fork)

En local, le projet fonctionne tel quel : il déploie les images publiques et signées de
`ghcr.io/tunsay`. Pour que **ta propre CI** publie, signe et déploie, remplace `tunsay` par ton
compte dans :

- `k8s/policies/values.yaml` — registre admis et identité du signataire ;
- `k8s/chart/values.yaml` — registre des images ;
- `k8s/argocd/values.yaml` — dépôt suivi par ArgoCD ;
- `scripts/promote.sh`, `scripts/admission-proof.sh`, `scripts/supply-chain-proof.sh` — identité
  attendue et images de test ;
- `security/exceptions.yaml` — propriétaire des dérogations.

Puis rends publics tes paquets GHCR `ssf-api` et `ssf-web` après la première publication, et
déploie leurs digests avec `make promote SHA=<commit>`.
