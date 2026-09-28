# Ingress controller : Traefik (ADR 0007).
#
# Pas ingress-nginx : le projet Kubernetes l'a retiré en mars 2026 (dépôt archivé, plus aucun
# correctif de sécurité). Traefik est maintenu, et son chart est conforme à PSS restricted sans
# rien modifier : non-root (UID 65532), système de fichiers en lecture seule, capacités retirées,
# seccomp RuntimeDefault.
#
# Exposition par NodePort, pas par hostPort : kube-proxy ouvre 30080/30443 sur chaque nœud, et
# la couche cluster relie ceux du control-plane à 127.0.0.1:8081/8444. Le pod reste un pod
# ordinaire, dans un namespace restricted. Au passage, un Service LoadBalancer (défaut du chart)
# ne recevrait jamais d'IP sur kind et bloquerait l'attente de Helm.

locals {
  ingress_class = "traefik"
}

resource "helm_release" "traefik" {
  name       = "traefik"
  namespace  = module.ns_ingress.name
  repository = "https://traefik.github.io/charts"
  chart      = "traefik"
  version    = "41.6.0"

  # Les CRD Traefik (IngressRoute, Middleware...) ne servent pas : on n'utilise que l'API
  # Ingress standard. Ne pas les installer réduit la surface et les droits du contrôleur.
  skip_crds = true
  wait      = true
  timeout   = 300

  values = [yamlencode({
    providers = {
      kubernetesCRD     = { enabled = false }
      kubernetesIngress = { enabled = true }
    }

    # Classe explicite, pas de classe par défaut : un Ingress qui ne la nomme pas n'est servi
    # par personne, plutôt que d'être exposé par surprise.
    ingressClass = {
      enabled        = true
      isDefaultClass = false
      name           = local.ingress_class
    }

    service = { spec = { type = "NodePort" } }
    ports = {
      web       = { nodePort = var.ingress_http_node_port }
      websecure = { nodePort = var.ingress_https_node_port }
    }

    # Pas de tableau de bord : c'est une interface d'administration de plus à protéger.
    api = { dashboard = false }

    # Aucun appel sortant vers traefik.io (vérification de version, statistiques).
    global = {
      checkNewVersion    = false
      sendAnonymousUsage = false
    }

    # Clé `accessLog` depuis les charts récents (anciennement `logs.access`) : le schéma du
    # chart refuse toute clé inconnue, l'erreur apparaît dès le plan.
    accessLog = { enabled = true }

    resources = {
      requests = { cpu = "50m", memory = "64Mi" }
      limits   = { cpu = "500m", memory = "256Mi" }
    }
  })]
}
