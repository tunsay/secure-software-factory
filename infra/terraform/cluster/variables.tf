variable "cluster_name" {
  description = "Nom du cluster kind. Apparaît dans le contexte kubeconfig (kind-<nom>)."
  type        = string
  default     = "ssf-dev"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.cluster_name))
    error_message = "Nom DNS-1123 : minuscules, chiffres, tirets."
  }
}

variable "node_image" {
  description = <<-EOT
    Image des nœuds kind, épinglée par digest : la version de Kubernetes est figée et vérifiable.
    Contrainte : le provider tehcyx/kind embarque sa propre bibliothèque kind (0.11.0 -> kind 0.31.0),
    qui ne sait générer la config kubeadm que pour les images de sa release. Prendre le digest
    dans les notes de release de CETTE version de kind, pas de la dernière.
    https://github.com/kubernetes-sigs/kind/releases/tag/v0.31.0
  EOT
  type        = string
  default     = "kindest/node:v1.35.0@sha256:452d707d4862f52530247495d180205e029056831160e22870e37e3f6c1ac31f"

  validation {
    condition     = can(regex("^kindest/node:v[0-9.]+@sha256:[a-f0-9]{64}$", var.node_image))
    error_message = "L'image doit être épinglée par digest sha256."
  }
}

variable "worker_count" {
  description = "Nombre de nœuds worker. Deux permettent de tester l'anti-affinité et les NetworkPolicies inter-nœuds."
  type        = number
  default     = 2

  validation {
    condition     = var.worker_count >= 1 && var.worker_count <= 3
    error_message = "Entre 1 et 3 workers sur un poste de travail."
  }
}

variable "ingress_http_port" {
  description = <<-EOT
    Port hôte relié au port 80 du control-plane (ingress).
    Pas 80 : sur Windows, 80 et 443 sont fréquemment réservés (service HTTP système, plages
    exclues Hyper-V) et le relais de Docker Desktop refuse de les publier. Pas 8080/8000 : ce sont
    ceux de docker compose, les deux environnements doivent coexister.
  EOT
  type        = number
  default     = 8081
}

variable "ingress_https_port" {
  description = "Port hôte relié au port 443 du control-plane (ingress). Voir ingress_http_port."
  type        = number
  default     = 8444
}

variable "kubeconfig_path" {
  description = "Chemin du kubeconfig écrit par kind. Hors du dépôt : il contient des certificats client."
  type        = string
  default     = "~/.kube/ssf-dev"
}
