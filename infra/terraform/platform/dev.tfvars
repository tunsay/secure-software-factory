# Environnement dev — aucune valeur sensible ici, ce fichier est commité.
environment   = "dev"
app_namespace = "ssf"
kube_context  = "kind-ssf-dev"

# La version de l'application n'est plus ici : depuis le jalon 5b, ArgoCD la lit dans
# k8s/chart/values-dev.yaml (déployer = un commit sur ce fichier). Terraform garde la plateforme.

# Politiques d'admission Kyverno : bloquantes. Phase Warn du 04/10 : nos images passaient sans
# avertissement, les autres étaient signalées par la bonne règle (journal du jalon 5).
admission_action = "Deny"
