# Observabilité (jalon 6b, ADR 0015) : la posture de sécurité, mesurée en continu.
#
# Jusqu'au jalon 6a, tous les contrôles empêchent, aucun ne raconte : un refus Kyverno, une
# dérive annulée par ArgoCD, une vulnérabilité publiée après le déploiement ne laissaient aucune
# trace consultable. Prometheus collecte, Grafana affiche (tableau de bord « posture sécurité »),
# des règles d'alerte signalent. Les sources : Kyverno, ArgoCD, Traefik, trivy-operator
# (trivy.tf), kube-state-metrics, et les métriques internes de l'API.

locals {
  monitoring_dir = "${path.module}/../../../k8s/monitoring"

  # Même principe que pour les autres charts locaux : un chart modifié sans changement de
  # version doit apparaître au plan.
  monitoring_checksum = sha256(join("", [
    for f in sort(fileset(local.monitoring_dir, "**")) : filesha256("${local.monitoring_dir}/${f}")
  ]))
}

# PSS restricted, comme les autres : tous les composants retenus s'y conforment.
module "ns_monitoring" {
  source = "../modules/namespace"

  name               = "monitoring"
  pod_security_level = "restricted"

  quota = {
    requests_cpu    = "2"
    requests_memory = "2Gi"
    limits_cpu      = "4"
    limits_memory   = "4Gi"
    pods            = 20
  }

  labels = {
    "app.kubernetes.io/part-of" = "secure-software-factory"
    "environment"               = var.environment
  }
}

resource "helm_release" "prometheus_stack" {
  name       = "kube-prometheus-stack"
  namespace  = module.ns_monitoring.name
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = "91.7.1" # prometheus-operator v0.94.1 (27/09/2026), délai de carence de 7 jours respecté

  wait    = true
  timeout = 600

  values = [yamlencode({
    # node-exporter exige un pod privilégié (hostNetwork, hostPID, montages du nœud) : interdit
    # par PSS restricted et par notre module de namespace. La posture de sécurité n'a pas besoin
    # des métriques système des nœuds. Même raison que l'abandon de kube-bench (jalon 5).
    nodeExporter = { enabled = false }

    # Pas d'Alertmanager : personne à prévenir sur un cluster de développement. Les alertes
    # restent calculées par Prometheus et visibles dans Grafana.
    alertmanager = { enabled = false }

    # Pas de règles ni de cibles par défaut : sur kind, contrôleur, ordonnanceur, etcd et proxy
    # écoutent sur 127.0.0.1, injoignables ; leurs alertes « down » seraient du bruit. On ne
    # garde que nos règles de sécurité (k8s/monitoring).
    defaultRules              = { create = false }
    kubernetesServiceMonitors = { enabled = false }

    prometheus = {
      prometheusSpec = {
        retention = "24h"
        # Prendre toutes les sondes et règles du cluster, pas seulement celles de ce chart.
        serviceMonitorSelectorNilUsesHelmValues = false
        podMonitorSelectorNilUsesHelmValues     = false
        ruleSelectorNilUsesHelmValues           = false
        resources = {
          requests = { cpu = "100m", memory = "384Mi" }
          limits   = { cpu = "1", memory = "1Gi" }
        }
      }
    }

    grafana = {
      # Seul notre tableau de bord, versionné dans k8s/monitoring.
      defaultDashboardsEnabled = false
      # Par défaut, le chart donne au « sidecar » de Grafana la lecture de TOUS les Secrets et
      # ConfigMaps du cluster (ClusterRole), état Terraform compris. Ici : son namespace seul.
      rbac = { namespaced = true }
      sidecar = {
        dashboards = { searchNamespace = module.ns_monitoring.name }
      }
      # Conteneur d'initialisation lancé en root (chown des données) : inutile sans volume
      # persistant, et interdit par PSS restricted.
      initChownData = { enabled = false }
      testFramework = { enabled = false }
      # Aucun mot de passe à connaître : formulaire de connexion désactivé, lecture anonyme en
      # lecture seule, accès par port-forward uniquement. Le mot de passe admin généré par le
      # chart reste dans un Secret du namespace, jamais dans le dépôt.
      "grafana.ini" = {
        "auth.anonymous" = { enabled = true, org_role = "Viewer" }
        auth             = { disable_login_form = true }
        users            = { allow_sign_up = false }
        # Aucun appel sortant (statistiques, vérification de version).
        analytics = { reporting_enabled = false, check_for_updates = false, check_for_plugin_updates = false }
      }
      resources = {
        requests = { cpu = "50m", memory = "128Mi" }
        limits   = { cpu = "500m", memory = "512Mi" }
      }
    }
  })]
}

# Sondes, règles d'alerte et tableau de bord de la posture de sécurité (chart local), après les
# CRD de Prometheus.
resource "helm_release" "monitoring_config" {
  name      = "ssf-monitoring"
  namespace = module.ns_monitoring.name
  chart     = local.monitoring_dir

  wait    = true
  timeout = 120

  values = [yamlencode({
    monitoringChecksum = local.monitoring_checksum
    appNamespace       = module.ns_app.name
  })]

  depends_on = [helm_release.prometheus_stack]
}
