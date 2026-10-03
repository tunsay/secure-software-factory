terraform {
  required_version = ">= 1.10, < 2.0"

  required_providers {
    kind = {
      source  = "tehcyx/kind"
      version = "~> 0.11"
    }
  }

  # Bootstrap : état local, comme le bootstrap d'un backend cloud.
  #
  # Cet état contient la clé privée administrateur du cluster, en clair : le provider tehcyx/kind
  # ne la déclare pas sensible (incident I2 du jalon 3). Il est donc rangé HORS du dépôt, dans le
  # dossier personnel WSL (~/.local/state/ssf/, droits 700), et non plus dans ce dossier, même
  # ignoré par git (journal du jalon 4, J4-I6). Chemin passé par `make infra-up`
  # (-backend-config) : le bloc backend n'accepte pas de fonction comme pathexpand.
  backend "local" {}
}
