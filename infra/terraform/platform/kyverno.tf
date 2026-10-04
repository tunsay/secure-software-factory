# Admission : Kyverno et les politiques du namespace applicatif (jalon 5a, ADR 0012).
#
# Ordre : Kyverno (et ses CRD) → politiques → application. L'application vient en dernier pour
# que ses propres pods passent par la vérification de signature à leur création : sur un cluster
# neuf (e2e), c'est la preuve que la chaîne admet ce qu'elle a signé.

locals {
  policies_dir = "${path.module}/../../../k8s/policies"

  # Même principe que pour le chart de l'application (app.tf) : un chart local modifié sans
  # changement de version doit apparaître au plan.
  policies_checksum = sha256(join("", [
    for f in sort(fileset(local.policies_dir, "**")) : filesha256("${local.policies_dir}/${f}")
  ]))
}

resource "helm_release" "kyverno" {
  name       = "kyverno"
  namespace  = module.ns_security.name
  repository = "https://kyverno.github.io/kyverno/"
  chart      = "kyverno"
  version    = "3.9.1" # Kyverno v1.19.1 (10/09/2026), délai de carence de 7 jours respecté

  wait    = true
  timeout = 600

  # Une réplique par contrôleur : cluster de développement, quota du namespace security.
  # Le chart est conforme à PSS restricted par défaut (non-root, capacités retirées, seccomp,
  # lecture seule), y compris ses jobs d'installation : aucune exception.
  values = [yamlencode({
    admissionController  = { replicas = 1 }
    backgroundController = { replicas = 1 }
    cleanupController    = { replicas = 1 }
    reportsController    = { replicas = 1 }
  })]
}

resource "helm_release" "admission_policies" {
  name      = "ssf-policies"
  namespace = module.ns_security.name
  chart     = local.policies_dir

  wait    = true
  timeout = 120

  values = [yamlencode({
    policiesChecksum = local.policies_checksum
    action           = var.admission_action
    namespace        = module.ns_app.name
  })]

  # Les types ImageValidatingPolicy / ValidatingPolicy sont des CRD installées par Kyverno.
  depends_on = [helm_release.kyverno]
}
