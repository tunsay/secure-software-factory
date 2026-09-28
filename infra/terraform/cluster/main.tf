# Cluster kind : un control-plane, N workers, image épinglée par digest.
# L'ingress (Traefik, jalon 3) est joint par un Service NodePort : kube-proxy ouvre le port
# sur chaque nœud, et seul celui du control-plane est relié à l'hôte. Aucun pod n'a besoin de
# hostPort, interdit par PSS restricted : l'ingress controller tourne sans exception.
# Pas 8080/8000 côté hôte : ce sont ceux de docker compose, les deux environnements coexistent.

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

      # Plus de patch kubeadm (étiquette ingress-ready) depuis le jalon 3 : avec un NodePort,
      # l'ingress n'a plus à tourner sur ce nœud. Le patch était aussi le point le plus fragile
      # du cluster (format map/liste selon la version de kind embarquée, voir rapport jalon 2).

      # listen_address 127.0.0.1 : l'app n'est joignable que depuis ce poste, pas depuis le
      # réseau local. Par défaut kind publie sur 0.0.0.0, soit toutes les interfaces.
      extra_port_mappings {
        container_port = var.ingress_http_node_port
        host_port      = var.ingress_http_port
        listen_address = "127.0.0.1"
        protocol       = "TCP"
      }
      extra_port_mappings {
        container_port = var.ingress_https_node_port
        host_port      = var.ingress_https_port
        listen_address = "127.0.0.1"
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
