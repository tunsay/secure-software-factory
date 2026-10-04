output "namespaces" {
  description = "Namespaces gérés par Terraform."
  value = {
    app      = module.ns_app.name
    ingress  = module.ns_ingress.name
    security = module.ns_security.name
    argocd   = module.ns_argocd.name
  }
}

output "argocd_revision" {
  description = "Révision du dépôt suivie par ArgoCD. La version de l'application est dans k8s/chart/values-dev.yaml."
  value       = var.argocd_revision
}
