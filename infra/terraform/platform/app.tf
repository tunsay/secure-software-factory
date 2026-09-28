# Application : chart Helm maison (k8s/chart), installé depuis le dépôt.
# Transitoire : au jalon 5, ArgoCD reprend le déploiement de l'app et ce fichier disparaît.
# Terraform garde la plateforme (namespaces, ingress, politiques), ArgoCD l'applicatif.

locals {
  chart_dir = "${path.module}/../../../k8s/chart"

  # Empreinte de tous les fichiers du chart. Le provider helm ne relit pas un chart local dont
  # la version n'a pas bougé : sans cette valeur, modifier un template ne produirait aucun
  # changement au plan, et le cluster garderait l'ancienne version en silence.
  chart_checksum = sha256(join("", [
    for f in sort(fileset(local.chart_dir, "**")) : filesha256("${local.chart_dir}/${f}")
  ]))
}

resource "helm_release" "app" {
  name      = "ssf"
  namespace = module.ns_app.name
  chart     = local.chart_dir

  # Pas d'atomic : en cas d'échec, les pods restent en place pour `kubectl describe`, au lieu
  # d'être effacés par un rollback automatique qui ferait disparaître le diagnostic.
  wait    = true
  timeout = 180

  values = [yamlencode({
    chartChecksum = local.chart_checksum
    image = {
      registry = var.image_registry
      tag      = var.image_tag
    }
    ingress = { className = local.ingress_class }
    api     = { env = { APP_ENV = var.environment } }
  })]

  # L'Ingress de l'app n'est servi qu'une fois la classe Traefik déclarée.
  depends_on = [helm_release.traefik]
}
