# ADR 0009 — Cloisonnement réseau : preuve sur cluster éphémère en CI, kindnet conservé

**Statut** : accepté · **Date** : 2026-10-03 · **Complète** l'ADR 0008

## Contexte

Les NetworkPolicies de l'ADR 0008 sont créées sans erreur, mais **ne sont pas appliquées** sur
le poste de développement (journal du jalon 3, incident I8). kindnet les traduit en règles
nftables qui utilisent l'instruction `queue` ; elle demande `CONFIG_NFT_QUEUE`, absent du noyau
WSL2 de Microsoft (5.15.167). Le noyau refuse les règles, kindnet abandonne, le trafic passe.

Le reste du noyau WSL2 a été vérifié : il fournit tout ce que Calico demande (ipset, conntrack,
rpfilter, VXLAN...). Remplacer kindnet était donc possible.

## Décision

- **kindnet est conservé.** Les NetworkPolicies restent écrites en Terraform, à l'identique.
- **La preuve se fait en CI**, workflow `e2e` : un runner `ubuntu-24.04` (noyau avec
  `NFT_QUEUE`) construit le cluster avec **les mêmes cibles make** qu'en local
  (`make infra-up TF_APPLY_FLAGS=-auto-approve`), puis exige l'« après » complet avec
  `make isolation-check`, qui échoue si un seul des huit tests diffère de l'attendu. Puis
  `make app-proof` vérifie la non-régression du jalon 3a.
- Déclenchement : à chaque changement de `infra/`, `k8s/`, du Makefile ou des sondes ; à la
  demande ; et chaque lundi, pour détecter une dérive extérieure sans commit.
- En local, `make isolation-check` **échoue** sur les tests réseau, et le dit. La limite reste
  visible, elle n'est pas masquée.

## Alternatives écartées

- **Remplacer kindnet par Calico** : protection réelle sur le poste, mais un composant réseau
  privilégié de plus à installer et maintenir, et une recréation du cluster. Reste la voie si le
  cluster local doit un jour servir de référence de sécurité.
- **Recompiler le noyau WSL2 avec `NFT_QUEUE`** : modifie le WSL de toute la machine, n'est pas
  reproductible depuis le dépôt, n'est pas de l'infrastructure as code.
- **Documenter sans prouver** : une politique jamais vue appliquée n'est qu'une intention.

## Conséquences

- La garantie du cloisonnement réseau vaut **là où le noyau le permet**, et c'est prouvé à
  chaque changement. Le cluster local, lui, ne filtre pas le réseau : il sert au développement,
  pas de référence de sécurité.
- La partie identité (jetons, droits de Traefik) ne dépend pas du noyau : prouvée en local
  **et** en CI.
- Le workflow `e2e` est un premier environnement éphémère : le jalon 6 (DAST avec ZAP) s'appuiera
  dessus.
- Le runner est figé (`ubuntu-24.04`), pas `ubuntu-latest` : le résultat dépend du noyau.
- Écart de versions connu : `kubectl` 1.37 sur le runner, cluster en 1.35 (au-delà de l'écart
  d'une version mineure officiellement supporté). Commandes utilisées stables ; à surveiller.
