# Scan continu des images qui tournent (jalon 6b, ADR 0015) : trivy-operator.
#
# La CI scanne chaque image au build (Trivy, depuis le jalon 1). Une faille publiée APRÈS le
# déploiement lui échappe : trivy-operator rescanne en continu les images du namespace
# applicatif et la configuration de ses objets, et publie le résultat en métriques Prometheus.
#
# Droits écrits ici, pas ceux du chart (décision de Tunsay, journal du jalon 6, V8). Par défaut,
# le chart lui donne la lecture de tous les Secrets du cluster et la création de Jobs dans tous
# les namespaces : un scanner compromis pourrait lancer un pod privilégié dans kube-system. Ici :
# lecture de ssf, Jobs de scan dans security seulement, aucun Secret hors de son namespace.

locals {
  trivy_sa = "trivy-operator"

  trivy_reports_verbs = ["create", "delete", "get", "list", "patch", "update", "watch"]
}

resource "helm_release" "trivy_operator" {
  name       = "trivy-operator"
  namespace  = module.ns_security.name
  repository = "https://aquasecurity.github.io/helm-charts/"
  chart      = "trivy-operator"
  version    = "0.36.0" # trivy-operator v0.34.0 (24/08/2026)

  wait    = true
  timeout = 300

  values = [yamlencode({
    # Seul le namespace applicatif est surveillé : le cache de l'opérateur se limite alors à ssf
    # et à son propre namespace (vérifié dans le source v0.34.0, pkg/operator/operator.go).
    targetNamespaces = module.ns_app.name

    # Droits écrits ci-dessous ; le chart ne crée que le compte de service.
    rbac           = { create = false }
    serviceAccount = { create = true, name = local.trivy_sa }

    operator = {
      # Images publiques : aucun secret d'accès au registre à lire, nulle part.
      accessGlobalSecretsAndServiceAccount = false
      scanJobsConcurrentLimit              = 1
      vulnerabilityScannerEnabled          = true
      configAuditScannerEnabled            = true
      exposedSecretScannerEnabled          = true
      # Hors sujet ici (SBOM déjà attesté au build), ou exigent des pods privilégiés sur les
      # nœuds (node-collector) :
      sbomGenerationEnabled         = false
      rbacAssessmentScannerEnabled  = false
      infraAssessmentScannerEnabled = false
      clusterComplianceEnabled      = false
    }

    # Pods de scan conformes à PSS restricted (namespace security) : non-root explicite, l'image
    # de Trivy tournant en root par défaut.
    trivyOperator = {
      scanJobPodTemplatePodSecurityContext = {
        runAsNonRoot   = true
        runAsUser      = 10000
        runAsGroup     = 10000
        fsGroup        = 10000
        seccompProfile = { type = "RuntimeDefault" }
      }
    }

    podSecurityContext = {
      runAsNonRoot   = true
      runAsUser      = 10000
      runAsGroup     = 10000
      seccompProfile = { type = "RuntimeDefault" }
    }

    resources = {
      requests = { cpu = "50m", memory = "128Mi" }
      limits   = { cpu = "500m", memory = "512Mi" }
    }

    serviceMonitor = { enabled = true }
  })]

  depends_on = [
    helm_release.prometheus_stack,
    kubernetes_role_binding_v1.trivy_read_app,
    kubernetes_role_binding_v1.trivy_read_own,
    kubernetes_role_binding_v1.trivy_own,
    kubernetes_cluster_role_binding_v1.trivy_cluster,
  ]
}

# Lecture des objets surveillés, écriture des rapports. Une ClusterRole, mais accordée par des
# RoleBindings : elle ne vaut que dans ssf (la cible) et dans security (ses propres Jobs).
resource "kubernetes_cluster_role_v1" "trivy_read" {
  metadata {
    name = "trivy-operator-lecture"
  }

  rule {
    api_groups = [""]
    resources  = ["configmaps", "limitranges", "persistentvolumeclaims", "pods", "replicationcontrollers", "resourcequotas", "serviceaccounts", "services"]
    verbs      = ["get", "list", "watch"]
  }
  rule {
    api_groups = [""]
    resources  = ["pods/log"]
    verbs      = ["get", "list"]
  }
  rule {
    api_groups = ["apps"]
    resources  = ["daemonsets", "deployments", "replicasets", "statefulsets"]
    verbs      = ["get", "list", "watch"]
  }
  rule {
    api_groups = ["batch"]
    resources  = ["cronjobs", "jobs"]
    verbs      = ["get", "list", "watch"]
  }
  rule {
    api_groups = ["networking.k8s.io"]
    resources  = ["ingresses", "networkpolicies"]
    verbs      = ["get", "list", "watch"]
  }
  rule {
    api_groups = ["rbac.authorization.k8s.io"]
    resources  = ["rolebindings", "roles"]
    verbs      = ["get", "list", "watch"]
  }
  rule {
    api_groups = ["aquasecurity.github.io"]
    resources  = ["configauditreports", "exposedsecretreports", "infraassessmentreports", "rbacassessmentreports", "sbomreports", "vulnerabilityreports"]
    verbs      = local.trivy_reports_verbs
  }
}

resource "kubernetes_role_binding_v1" "trivy_read_app" {
  metadata {
    name      = "trivy-operator-lecture"
    namespace = module.ns_app.name
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.trivy_read.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = local.trivy_sa
    namespace = module.ns_security.name
  }
}

resource "kubernetes_role_binding_v1" "trivy_read_own" {
  metadata {
    name      = "trivy-operator-lecture"
    namespace = module.ns_security.name
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.trivy_read.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = local.trivy_sa
    namespace = module.ns_security.name
  }
}

# Dans son propre namespace seulement : créer ses Jobs de scan, ses Secrets et ConfigMaps de
# travail, et l'élection de leader. Nulle part ailleurs.
resource "kubernetes_role_v1" "trivy_own" {
  metadata {
    name      = "trivy-operator"
    namespace = module.ns_security.name
  }

  rule {
    api_groups = ["batch"]
    resources  = ["jobs"]
    verbs      = ["create", "delete"]
  }
  rule {
    api_groups = [""]
    resources  = ["secrets"]
    verbs      = ["create", "delete", "get", "update"]
  }
  rule {
    api_groups = [""]
    resources  = ["configmaps"]
    verbs      = ["create", "delete", "get", "list", "patch", "update", "watch"]
  }
  rule {
    api_groups = ["coordination.k8s.io"]
    resources  = ["leases"]
    verbs      = ["create", "get", "update"]
  }
  rule {
    api_groups = [""]
    resources  = ["events"]
    verbs      = ["create"]
  }
}

resource "kubernetes_role_binding_v1" "trivy_own" {
  metadata {
    name      = "trivy-operator"
    namespace = module.ns_security.name
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.trivy_own.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = local.trivy_sa
    namespace = module.ns_security.name
  }
}

# Niveau cluster, en lecture seule (nœuds, namespaces, définitions de ressources) et sur ses
# seuls rapports de niveau cluster. Ni Secret, ni Job, ni droit d'écriture sur autre chose.
resource "kubernetes_cluster_role_v1" "trivy_cluster" {
  metadata {
    name = "trivy-operator-cluster"
  }

  rule {
    api_groups = [""]
    resources  = ["namespaces", "nodes"]
    verbs      = ["get", "list", "watch"]
  }
  rule {
    api_groups = ["apiextensions.k8s.io"]
    resources  = ["customresourcedefinitions"]
    verbs      = ["get", "list", "watch"]
  }
  rule {
    api_groups = ["aquasecurity.github.io"]
    resources  = ["clustercompliancedetailreports", "clustercompliancereports", "clusterconfigauditreports", "clusterinfraassessmentreports", "clusterrbacassessmentreports", "clustersbomreports", "clustervulnerabilityreports"]
    verbs      = local.trivy_reports_verbs
  }
}

resource "kubernetes_cluster_role_binding_v1" "trivy_cluster" {
  metadata {
    name = "trivy-operator-cluster"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role_v1.trivy_cluster.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = local.trivy_sa
    namespace = module.ns_security.name
  }
}
