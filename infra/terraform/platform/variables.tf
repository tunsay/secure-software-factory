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

variable "argocd_revision" {
  description = <<-EOT
    Révision du dépôt que suit ArgoCD : main en local ; le SHA exact du commit testé dans le
    workflow e2e (make infra-up TF_PLATFORM_VARS=-var=argocd_revision=<sha>). La version de
    l'application, elle, est dans k8s/chart/values-dev.yaml, pas ici (jalon 5b, ADR 0014).
  EOT
  type        = string
  default     = "main"

  validation {
    condition     = var.argocd_revision == "main" || can(regex("^[0-9a-f]{40}$", var.argocd_revision))
    error_message = "main, ou un SHA de commit complet (40 caractères hexadécimaux)."
  }
}

variable "admission_action" {
  description = <<-EOT
    Action des politiques d'admission Kyverno sur le namespace applicatif.
    Deny : refuser. Warn : admettre mais avertir (mise en place, pour voir ce qui serait refusé
    avant de bloquer). Audit : admettre et consigner dans les rapports.
  EOT
  type        = string
  default     = "Deny"

  validation {
    condition     = contains(["Deny", "Warn", "Audit"], var.admission_action)
    error_message = "Deny, Warn ou Audit."
  }
}

variable "ingress_http_node_port" {
  description = "NodePort HTTP de Traefik. Doit être identique à la variable du même nom dans la couche cluster."
  type        = number
  default     = 30080
}

variable "ingress_https_node_port" {
  description = "NodePort HTTPS de Traefik. Doit être identique à la variable du même nom dans la couche cluster."
  type        = number
  default     = 30443
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
