variable "kubeconfig_path" {
  description = "Kubeconfig écrit par la couche cluster."
  type        = string
  default     = "~/.kube/ssf-dev"
}

variable "kube_context" {
  description = "Contexte kubeconfig à utiliser. Explicite pour ne jamais appliquer sur le mauvais cluster."
  type        = string
  default     = "kind-ssf-dev"
}

variable "app_namespace" {
  description = "Namespace applicatif."
  type        = string
  default     = "ssf"
}

variable "environment" {
  description = "Nom d'environnement, propagé en étiquette."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "dev, staging ou prod."
  }
}
