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

variable "image_registry" {
  description = "Registre et propriétaire des images applicatives."
  type        = string
  default     = "ghcr.io/tunsay"
}

variable "image_tag" {
  description = <<-EOT
    Tag des images ssf-api et ssf-web : le SHA complet d'un commit de main, publié par la CI.
    Jamais latest : un tag mobile ne dit pas ce qui tourne. Jalon 4 : passage au digest.
  EOT
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{40}$", var.image_tag))
    error_message = "SHA de commit complet (40 caractères hexadécimaux) attendu."
  }
}

variable "image_digests" {
  description = <<-EOT
    Digest de chaque image, publiée et signée par la CI pour ce commit (résumé du job « images »).
    C'est lui qui fait foi au tirage : un tag peut être déplacé dans le registre, un digest
    désigne un contenu unique (jalon 4, ADR 0010).
  EOT
  type = object({
    api = string
    web = string
  })

  validation {
    condition     = alltrue([for d in values(var.image_digests) : can(regex("^sha256:[0-9a-f]{64}$", d))])
    error_message = "Digest sha256 complet attendu pour chaque image (sha256: suivi de 64 caractères hexadécimaux)."
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
