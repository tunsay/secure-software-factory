variable "name" {
  description = "Nom du namespace."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.name))
    error_message = "Nom DNS-1123 : minuscules, chiffres, tirets."
  }
}

variable "pod_security_level" {
  description = "Niveau Pod Security Standards appliqué en enforce/audit/warn. 'restricted' est la cible ; 'baseline' uniquement pour les namespaces système qui ne peuvent pas faire mieux."
  type        = string
  default     = "restricted"

  validation {
    condition     = contains(["baseline", "restricted"], var.pod_security_level)
    error_message = "Valeurs admises : baseline, restricted. 'privileged' n'est jamais accepté par ce module."
  }
}

variable "quota" {
  description = "Quota de ressources du namespace. Borne ce qu'un déploiement défaillant ou compromis peut consommer."
  type = object({
    requests_cpu    = string
    requests_memory = string
    limits_cpu      = string
    limits_memory   = string
    pods            = number
  })
  default = {
    requests_cpu    = "1"
    requests_memory = "1Gi"
    limits_cpu      = "2"
    limits_memory   = "2Gi"
    pods            = 20
  }
}

variable "default_container_limits" {
  description = "Limites et requêtes par défaut injectées dans tout conteneur qui n'en déclare pas. Sans ça, un pod sans limites est accepté par le quota et peut saturer le nœud."
  type = object({
    default_cpu            = string
    default_memory         = string
    default_request_cpu    = string
    default_request_memory = string
  })
  default = {
    default_cpu            = "250m"
    default_memory         = "256Mi"
    default_request_cpu    = "50m"
    default_request_memory = "64Mi"
  }
}

variable "labels" {
  description = "Étiquettes supplémentaires."
  type        = map(string)
  default     = {}
}
