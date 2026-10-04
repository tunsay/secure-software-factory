# Environnement dev — aucune valeur sensible ici, ce fichier est commité.
environment   = "dev"
app_namespace = "ssf"
kube_context  = "kind-ssf-dev"

# Version déployée : changer ces lignes est l'acte de déploiement, visible dans le plan.
# Valeurs à reprendre du résumé du job « images » de la CI (images publiées ET signées).
# Le tag est informatif ; c'est le digest qui fait foi au tirage.
image_tag = "ddbf88f56ea55b4ac122314c07f420d6c65f95ae"
image_digests = {
  api = "sha256:49e6c08aa84ef1596346cf742a6aa0a97108ee05a083fcc2819668729f2e0ee8"
  web = "sha256:69c197b5009c0781d69a24f7cf90c829e0471101c671e960a3b4d5c4c65968e4"
}

# Politiques d'admission Kyverno : bloquantes. Phase Warn du 04/10 : nos images passaient sans
# avertissement, les autres étaient signalées par la bonne règle (journal du jalon 5).
admission_action = "Deny"
