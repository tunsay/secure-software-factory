terraform {
  required_version = ">= 1.10, < 2.0"

  required_providers {
    kind = {
      source  = "tehcyx/kind"
      version = "~> 0.11"
    }
  }

  # Bootstrap : état local, comme le bootstrap d'un backend cloud.
  # Le fichier terraform.tfstate est ignoré par git (voir .gitignore).
}
