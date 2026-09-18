output "namespaces" {
  description = "Namespaces gérés par Terraform."
  value = {
    app      = module.ns_app.name
    security = module.ns_security.name
  }
}
