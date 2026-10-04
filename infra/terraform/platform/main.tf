# Couche platform : ce qui tourne dans le cluster.
# Jalon 2 : namespaces durcis. Jalon 3 : ingress (ingress.tf), NetworkPolicies, RBAC.
# Jalon 5 : Kyverno (kyverno.tf), ArgoCD (argocd.tf), qui déploie l'application depuis le dépôt.
# Jalon 6 : Prometheus, Grafana.

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

# Namespace de l'ingress controller. restricted lui aussi : Traefik est joint par NodePort,
# il n'a besoin ni de hostPort ni de privilège (voir ingress.tf).
module "ns_ingress" {
  source = "../modules/namespace"

  name               = "ingress"
  pod_security_level = "restricted"

  labels = {
    "app.kubernetes.io/part-of" = "secure-software-factory"
    "environment"               = var.environment
  }
}

# Namespace des outils de sécurité : Kyverno, trivy-operator et ses Jobs de scan (jalon 6b).
# Quota plus large : ce sont des contrôleurs, pas des workloads applicatifs.
module "ns_security" {
  source = "../modules/namespace"

  name               = "security"
  pod_security_level = "restricted"

  quota = {
    requests_cpu    = "1500m"
    requests_memory = "2Gi"
    limits_cpu      = "4"
    limits_memory   = "4Gi"
    pods            = 30
  }

  labels = {
    "app.kubernetes.io/part-of" = "secure-software-factory"
    "environment"               = var.environment
  }
}
