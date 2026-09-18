# Namespace durci.
#
# Pod Security Standards en mode enforce : l'API server refuse tout pod qui viole le niveau
# (root, privilégié, capacités ajoutées, hostPath, hostNetwork...). C'est un contrôle
# d'admission intégré à Kubernetes, sans composant à installer. Kyverno (jalon 5) viendra
# par-dessus pour les règles que PSS ne couvre pas (signature, tag latest, registre autorisé).

resource "kubernetes_namespace_v1" "this" {
  metadata {
    name = var.name

    labels = merge(
      {
        "pod-security.kubernetes.io/enforce"         = var.pod_security_level
        "pod-security.kubernetes.io/enforce-version" = "latest"
        "pod-security.kubernetes.io/audit"           = "restricted"
        "pod-security.kubernetes.io/warn"            = "restricted"
        "app.kubernetes.io/managed-by"               = "terraform"
      },
      var.labels,
    )
  }
}

# Quota : plafond global du namespace.
resource "kubernetes_resource_quota_v1" "this" {
  metadata {
    name      = "quota"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
  }

  spec {
    hard = {
      "requests.cpu"    = var.quota.requests_cpu
      "requests.memory" = var.quota.requests_memory
      "limits.cpu"      = var.quota.limits_cpu
      "limits.memory"   = var.quota.limits_memory
      "pods"            = tostring(var.quota.pods)
    }
  }
}

# LimitRange : valeurs par défaut par conteneur. Un pod sans limites déclarées en reçoit,
# donc aucun conteneur ne tourne sans borne.
resource "kubernetes_limit_range_v1" "this" {
  metadata {
    name      = "defaults"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
  }

  spec {
    limit {
      type = "Container"
      default = {
        cpu    = var.default_container_limits.default_cpu
        memory = var.default_container_limits.default_memory
      }
      default_request = {
        cpu    = var.default_container_limits.default_request_cpu
        memory = var.default_container_limits.default_request_memory
      }
    }
  }
}
