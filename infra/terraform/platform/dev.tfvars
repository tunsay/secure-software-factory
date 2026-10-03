# Environnement dev — aucune valeur sensible ici, ce fichier est commité.
environment   = "dev"
app_namespace = "ssf"
kube_context  = "kind-ssf-dev"

# Version déployée : changer ces lignes est l'acte de déploiement, visible dans le plan.
# Valeurs à reprendre du résumé du job « images » de la CI (images publiées ET signées).
# Le tag est informatif ; c'est le digest qui fait foi au tirage.
image_tag = "f159b944b9f7b2b4e2ffb87c2fe6b097fdc1a24a"
image_digests = {
  api = "sha256:a0269bc4f1a0674940d19a8ecd6b189e41680fbda4820383d66b62dfed8f6ef7"
  web = "sha256:2395df19284130fb2007b023b3d1137912da14ee2f348e0e98d349e24b8799d5"
}
