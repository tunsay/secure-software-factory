# GitOps (jalon 5b, ADR 0014) : ArgoCD déploie l'application depuis CE dépôt — chart k8s/chart,
# valeurs k8s/chart/values-dev.yaml — et annule toute modification manuelle (selfHeal).
#
# Partage des rôles : Terraform garde la plateforme (namespaces, ingress, NetworkPolicies,
# Kyverno, et les droits d'ArgoCD lui-même) ; ArgoCD l'applicatif. Déployer une version = un
# commit sur values-dev.yaml ; personne n'applique l'application à la main.
#
# Ordre sur un cluster neuf (e2e) : ArgoCD, Kyverno et Traefik → droits d'ArgoCD dans ssf →
# projet et Application. Les pods de l'application passent donc par Kyverno à leur création.

locals {
  argocd_app_dir = "${path.module}/../../../k8s/argocd"

  # Même principe que pour les politiques (kyverno.tf) : un chart local modifié sans changement
  # de version doit apparaître au plan.
  argocd_app_checksum = sha256(join("", [
    for f in sort(fileset(local.argocd_app_dir, "**")) : filesha256("${local.argocd_app_dir}/${f}")
  ]))

  # Types d'objets du chart applicatif : les seuls qu'ArgoCD peut écrire dans ssf. Même liste
  # que namespaceResourceWhitelist du projet (k8s/argocd/templates/project.yaml).
  argocd_managed = [
    { api_groups = ["apps"], resources = ["deployments"] },
    { api_groups = [""], resources = ["services", "serviceaccounts"] },
    { api_groups = ["networking.k8s.io"], resources = ["ingresses"] },
  ]
  # Lus seulement, pour l'état de santé et l'arbre des ressources.
  argocd_observed = [
    { api_groups = ["apps"], resources = ["replicasets"] },
    { api_groups = [""], resources = ["pods"] },
  ]
}

# Namespace d'ArgoCD, PSS restricted : le chart est conforme par défaut (non-root, lecture
# seule, capacités retirées, seccomp), Redis et son job d'initialisation compris.
module "ns_argocd" {
  source = "../modules/namespace"

  name               = "argocd"
  pod_security_level = "restricted"

  # Des contrôleurs, comme dans security : quota plus large qu'un namespace applicatif.
  quota = {
    requests_cpu    = "1"
    requests_memory = "1Gi"
    limits_cpu      = "3"
    limits_memory   = "3Gi"
    pods            = 20
  }

  labels = {
    "app.kubernetes.io/part-of" = "secure-software-factory"
    "environment"               = var.environment
  }
}

resource "helm_release" "argocd" {
  name       = "argocd"
  namespace  = module.ns_argocd.name
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "10.9.2" # Argo CD v3.5.3 (14/09/2026), délai de carence de 7 jours respecté

  wait    = true
  timeout = 600

  values = [yamlencode({
    # Aucun rôle de cluster. Par défaut, le chart donne au contrôleur une ClusterRole « * » sur
    # « * » : un ArgoCD compromis, ou un commit malveillant, prendrait tout le cluster. Ici, ses
    # seuls droits hors de son namespace sont les Roles ci-dessous, dans ssf.
    createClusterRoles = false

    configs = {
      # Le cluster local, restreint au namespace applicatif. Sans identifiants : ArgoCD utilise le
      # compte de service de son pod (vérifié dans le source v3.5.3, Cluster.RawRestConfig).
      clusterCredentials = {
        "in-cluster" = {
          server     = "https://kubernetes.default.svc"
          namespaces = module.ns_app.name
          config     = {}
        }
      }
      cm = {
        # Ne surveiller que les types d'objets que ses droits permettent de lister : sans ça,
        # chaque type interdit (Secrets, Roles...) fait échouer la lecture du namespace.
        "resource.respectRBAC" = "normal"
        # Aucun compte, donc aucun mot de passe : pas d'admin. L'interface est en lecture seule,
        # sans connexion, joignable seulement par port-forward. Seul Git déploie.
        "admin.enabled"           = false
        "users.anonymous.enabled" = true
      }
      rbac = { "policy.default" = "role:readonly" }
    }

    # Absents car inutiles : pas de SSO (dex), pas de notifications, pas d'ApplicationSet (une
    # seule application). Moins de composants, moins de surface.
    dex            = { enabled = false }
    notifications  = { enabled = false }
    applicationSet = { replicas = 0 }

    controller = {
      # Métriques Prometheus (jalon 6b) : argocd_app_info, état de synchronisation et santé.
      metrics = {
        enabled        = true
        serviceMonitor = { enabled = true }
      }
      resources = {
        requests = { cpu = "100m", memory = "256Mi" }
        limits   = { cpu = "1", memory = "768Mi" }
      }
    }
    repoServer = {
      resources = {
        requests = { cpu = "50m", memory = "128Mi" }
        limits   = { cpu = "500m", memory = "512Mi" }
      }
    }
    server = {
      resources = {
        requests = { cpu = "20m", memory = "64Mi" }
        limits   = { cpu = "200m", memory = "256Mi" }
      }
    }
    redis = {
      resources = {
        requests = { cpu = "20m", memory = "32Mi" }
        limits   = { cpu = "200m", memory = "128Mi" }
      }
    }
  })]

  # La sonde est un objet ServiceMonitor : ses CRD viennent de kube-prometheus-stack.
  depends_on = [helm_release.prometheus_stack]
}

# Droits du contrôleur dans ssf, portés par la plateforme (ADR 0008) et visibles au plan :
# écrire les seuls types d'objets du chart applicatif, lire leurs dépendants. Rien sur les
# Secrets, les Roles, les NetworkPolicies, les quotas, ni ailleurs que dans ssf.
resource "kubernetes_role_v1" "argocd_deployer" {
  metadata {
    name      = "argocd-deployer"
    namespace = module.ns_app.name
  }

  dynamic "rule" {
    for_each = local.argocd_managed
    content {
      api_groups = rule.value.api_groups
      resources  = rule.value.resources
      verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
    }
  }

  dynamic "rule" {
    for_each = local.argocd_observed
    content {
      api_groups = rule.value.api_groups
      resources  = rule.value.resources
      verbs      = ["get", "list", "watch"]
    }
  }
}

resource "kubernetes_role_binding_v1" "argocd_deployer" {
  metadata {
    name      = "argocd-deployer"
    namespace = module.ns_app.name
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.argocd_deployer.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = "argocd-application-controller"
    namespace = module.ns_argocd.name
  }
}

# Interface (argocd-server) : lecture seule des mêmes objets, pour afficher l'arbre et les
# manifestes en direct. Elle ne peut rien modifier dans ssf.
resource "kubernetes_role_v1" "argocd_viewer" {
  metadata {
    name      = "argocd-viewer"
    namespace = module.ns_app.name
  }

  dynamic "rule" {
    for_each = concat(local.argocd_managed, local.argocd_observed)
    content {
      api_groups = rule.value.api_groups
      resources  = rule.value.resources
      verbs      = ["get", "list", "watch"]
    }
  }
}

resource "kubernetes_role_binding_v1" "argocd_viewer" {
  metadata {
    name      = "argocd-viewer"
    namespace = module.ns_app.name
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.argocd_viewer.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = "argocd-server"
    namespace = module.ns_argocd.name
  }
}

# Projet et Application (chart local k8s/argocd) : après ArgoCD (ses CRD), après ses droits,
# et après Kyverno et Traefik, pour que l'application naisse sous les politiques d'admission.
resource "helm_release" "argocd_app" {
  name      = "ssf-argocd"
  namespace = module.ns_argocd.name
  chart     = local.argocd_app_dir

  wait    = true
  timeout = 120

  values = [yamlencode({
    argocdChecksum = local.argocd_app_checksum
    revision       = var.argocd_revision
    namespace      = module.ns_app.name
  })]

  depends_on = [
    helm_release.argocd,
    helm_release.admission_policies,
    helm_release.traefik,
    kubernetes_role_binding_v1.argocd_deployer,
  ]
}
