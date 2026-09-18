# Cluster kind : un control-plane, N workers, image épinglée par digest.
# Les ports 80/443 du control-plane sont exposés sur l'hôte pour l'ingress (jalon 3).
# Pas 8080/8000 : ce sont ceux de docker compose, les deux environnements doivent coexister.

resource "kind_cluster" "this" {
  name            = var.cluster_name
  node_image      = var.node_image
  kubeconfig_path = pathexpand(var.kubeconfig_path)
  wait_for_ready  = true

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    node {
      role = "control-plane"

      # Étiquette utilisée par l'ingress controller pour se placer sur ce nœud.
      #
      # ATTENTION au format : il dépend de la bibliothèque kind EMBARQUÉE dans le provider,
      # pas du kind installé sur le poste. Provider 0.11.0 -> kind 0.31 -> kubeadm v1beta3,
      # où kubeletExtraArgs est une map. Le kind 0.33 en ligne de commande génère du v1beta4,
      # où c'est une liste name/value : le même patch y échouerait, et inversement.
      # Diagnostic : `kind-0.31 create cluster --retain` puis lire "Command Output".
      kubeadm_config_patches = [
        <<-EOT
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "ingress-ready=true"
        EOT
      ]

      extra_port_mappings {
        container_port = 80
        host_port      = var.ingress_http_port
        protocol       = "TCP"
      }
      extra_port_mappings {
        container_port = 443
        host_port      = var.ingress_https_port
        protocol       = "TCP"
      }
    }

    dynamic "node" {
      for_each = range(var.worker_count)
      content {
        role = "worker"
      }
    }
  }
}
