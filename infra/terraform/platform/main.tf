# Couche platform : ce qui tourne dans le cluster et qui n'est pas l'application.
# Jalon 2 : namespaces durcis. Jalon 3 : NetworkPolicies, RBAC, Sealed Secrets.
# Jalon 5 : Kyverno, ArgoCD. Jalon 6 : Prometheus, Grafana.

# Namespace applicatif, PSS restricted : aucun pod root, privilégié ou avec capacités.
module "ns_app" {
  source = "../modules/namespace"

  name               = var.app_namespace
  pod_security_level = "restricted"

  labels = {
    "app.kubernetes.io/part-of" = "secure-software-factory"
    "environment"               = var.environment
  }
}

# Namespace des outils de sécurité (Kyverno, Sealed Secrets). Quota plus large : ce sont
# des contrôleurs, pas des workloads applicatifs.
module "ns_security" {
  source = "../modules/namespace"

  name               = "security"
  pod_security_level = "restricted"

  quota = {
    requests_cpu    = "1"
    requests_memory = "1Gi"
    limits_cpu      = "2"
    limits_memory   = "3Gi"
    pods            = 30
  }

  labels = {
    "app.kubernetes.io/part-of" = "secure-software-factory"
    "environment"               = var.environment
  }
}
