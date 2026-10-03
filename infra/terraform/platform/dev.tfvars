# Environnement dev — aucune valeur sensible ici, ce fichier est commité.
environment   = "dev"
app_namespace = "ssf"
kube_context  = "kind-ssf-dev"

# Version déployée : changer ces lignes est l'acte de déploiement, visible dans le plan.
# Valeurs à reprendre du résumé du job « images » de la CI (images publiées ET signées).
# Le tag est informatif ; c'est le digest qui fait foi au tirage.
image_tag = "ef53ba87374d630f3d5db367d845589c765bb405"
image_digests = {
  api = "sha256:783f41b69d1bf948dacf673a465165a4ba8a293367d38d1206125ff35f83b2c5"
  web = "sha256:d84eb2cbe363073fd2e42b604276484cc7038841407a1160755661868e15c01b"
}
