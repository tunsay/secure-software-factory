# Modèle de menaces (à compléter en semaine 6)

Méthode : STRIDE appliqué à la chaîne, pas à l'application. Renvoi vers les ateliers EBIOS RM
lorsqu'un scénario relève d'une source de risque identifiable.

| Élément | Menace (STRIDE) | Contrôle | Étage |
|---|---|---|---|
| Dépôt Git | Secrets commités (I) | gitleaks pre-commit + CI | S1 |
| Dépendances | Paquet vulnérable ou malveillant (T, E) | pip-audit, npm audit, SBOM | S1 / S4 |
| Image | CVE dans la base ou la couche applicative (E) | Trivy bloquant, base slim/unprivileged | S1 |
| Registre | Image non signée poussée à la main (S, T) | Cosign + vérification Kyverno à l'admission | S4 / S5 |
| Cluster | Pod root, escalade (E) | PSS restricted, Kyverno runAsNonRoot | S3 / S5 |
| Réseau interne | Mouvement latéral (I, E) | NetworkPolicies deny-by-default | S3 |
| CI | Clé cloud statique volée (S, I) | IAM OIDC, aucune clé | S2 |
| Front | XSS, injection de script tiers (T) | CSP stricte, aucune origine externe | S1 |
