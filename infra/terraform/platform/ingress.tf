# Ingress controller : Traefik (ADR 0007, droits restreints : ADR 0008).
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
    # Droits par namespace (jalon 3b, ADR 0008). Par défaut le chart crée une ClusterRole qui
    # donne à Traefik la lecture de TOUS les Secrets du cluster, état Terraform compris.
    # Ici : un Role dans son propre namespace et dans ssf, rien ailleurs.
    rbac = { namespaced = true }

    providers = {
      kubernetesCRD = { enabled = false }
      kubernetesIngress = {
        enabled    = true
        namespaces = [module.ns_app.name]
        # En mode namespacé, Traefik ne lit plus les IngressClass (objets de niveau cluster) et
        # ignore les Ingress qui en référencent une (spec.ingressClassName). Il sert ceux qui
        # portent l'annotation kubernetes.io/ingress.class de cette valeur, et aucun autre :
        # la classe reste explicite.
        ingressClass = local.ingress_class
        # Adresse publiée dans le statut des Ingress servis (jalon 5b). Par défaut, Traefik
        # recopie celle de son Service ; en NodePort, il n'en a pas : le statut restait vide,
        # et ArgoCD jugeait l'application « Progressing » sans fin (sa règle de santé d'un
        # Ingress : sain = une adresse publiée). 127.0.0.1 est l'adresse réelle d'accès.
        publishedService = { enabled = false }
        ingressEndpoint  = { ip = "127.0.0.1" }
      }
    }

    # Pas d'objet IngressClass : inutilisable en RBAC namespacé (voir ci-dessus).
    ingressClass = { enabled = false }

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
