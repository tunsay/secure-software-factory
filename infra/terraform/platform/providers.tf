provider "kubernetes" {
  config_path    = pathexpand(var.kubeconfig_path)
  config_context = var.kube_context
}

provider "helm" {
  # Pas d'experiments.manifest : essayé au jalon 3, il casse l'apply dès que le namespace cible
  # n'existe pas encore au moment du plan (journal jalon 3, incident I3). La détection des
  # changements du chart local passe par une empreinte (app.tf).
  kubernetes = {
    config_path    = pathexpand(var.kubeconfig_path)
    config_context = var.kube_context
  }
}
