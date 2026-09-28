output "namespaces" {
  description = "Namespaces gérés par Terraform."
  value = {
    app      = module.ns_app.name
    ingress  = module.ns_ingress.name
    security = module.ns_security.name
  }
}

output "image_tag" {
  description = "Version de l'application déployée."
  value       = var.image_tag
}
