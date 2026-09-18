output "cluster_name" {
  description = "Nom du cluster kind."
  value       = kind_cluster.this.name
}

output "kubeconfig_path" {
  description = "Chemin du kubeconfig à passer à la couche platform et à kubectl."
  value       = kind_cluster.this.kubeconfig_path
}

output "endpoint" {
  description = "Endpoint de l'API server."
  value       = kind_cluster.this.endpoint
}

output "context" {
  description = "Nom du contexte kubeconfig."
  value       = "kind-${kind_cluster.this.name}"
}
