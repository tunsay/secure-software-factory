terraform {
  required_version = ">= 1.10, < 2.0"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.30, < 3.3"
    }
  }

  # État distant : stocké dans un Secret du cluster, verrou par Lease.
  # Le namespace terraform-state est créé par `make infra-up` avant le premier init.
  # config_path est passé par `-backend-config` (le bloc backend n'accepte pas de fonction
  # comme pathexpand). C'est l'équivalent du backend S3 + verrou prévu sur AWS (ADR 0004).
  backend "kubernetes" {
    secret_suffix = "platform"
    namespace     = "terraform-state"
  }
}
