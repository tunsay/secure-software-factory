output "name" {
  description = "Nom du namespace créé."
  value       = kubernetes_namespace_v1.this.metadata[0].name
}
