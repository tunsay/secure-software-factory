# Cloisonnement réseau du namespace applicatif (jalon 3b, ADR 0008).
#
# Principe : tout est fermé, puis chaque flux légitime est ouvert un par un, en entrée ET en
# sortie. Il y en a trois : Traefik -> web, web -> api, et la résolution DNS ; plus, au jalon 6b,
# Prometheus -> api pour les métriques.
#
#   Internet / poste ──► Traefik (ns ingress) ──► web ──► api
#                                                  │       │
#                                                  └──┬────┘
#                                                     ▼
#                                              CoreDNS (kube-system)
#
# Tout le reste est refusé : api -> web, api -> Internet, tout autre pod du cluster -> api.
# Les politiques sont portées par la plateforme (Terraform), pas par le chart de l'application :
# celui qui déploie l'application (ArgoCD au jalon 5) ne doit pas pouvoir élargir ses propres flux.
#
# Appliquées par kindnet (kube-network-policies, depuis kind 0.24). Une politique ignorée par le
# réseau ne produit aucune erreur : la preuve est `make isolation-proof`, pas ce fichier.

locals {
  app_ns = module.ns_app.name

  # Étiquettes posées par le chart k8s/chart (ssf.selectorLabels).
  web_pods = { "app.kubernetes.io/name" = "ssf", "app.kubernetes.io/component" = "web" }
  api_pods = { "app.kubernetes.io/name" = "ssf", "app.kubernetes.io/component" = "api" }
}

# 1. Tout fermer : aucun flux entrant ni sortant pour aucun pod du namespace.
resource "kubernetes_network_policy_v1" "default_deny" {
  metadata {
    name      = "default-deny"
    namespace = local.app_ns
  }

  spec {
    pod_selector {}
    policy_types = ["Ingress", "Egress"]
  }
}

# 2. DNS : sans lui, `api` et `web` ne se résolvent plus. Uniquement vers CoreDNS, port 53.
resource "kubernetes_network_policy_v1" "allow_dns" {
  metadata {
    name      = "allow-dns"
    namespace = local.app_ns
  }

  spec {
    pod_selector {}
    policy_types = ["Egress"]

    egress {
      to {
        namespace_selector {
          match_labels = { "kubernetes.io/metadata.name" = "kube-system" }
        }
        pod_selector {
          match_labels = { "k8s-app" = "kube-dns" }
        }
      }
      ports {
        port     = "53"
        protocol = "UDP"
      }
      ports {
        port     = "53"
        protocol = "TCP"
      }
    }
  }
}

# 3. web n'accepte que Traefik. namespace_selector et pod_selector dans le même `from` :
#    les deux conditions à la fois (le pod Traefik, dans le namespace ingress).
resource "kubernetes_network_policy_v1" "web_from_traefik" {
  metadata {
    name      = "web-from-traefik"
    namespace = local.app_ns
  }

  spec {
    pod_selector {
      match_labels = local.web_pods
    }
    policy_types = ["Ingress"]

    ingress {
      from {
        namespace_selector {
          match_labels = { "kubernetes.io/metadata.name" = module.ns_ingress.name }
        }
        pod_selector {
          match_labels = { "app.kubernetes.io/name" = "traefik" }
        }
      }
      ports {
        port     = "8080"
        protocol = "TCP"
      }
    }
  }
}

# 4. web peut joindre api, et rien d'autre (hors DNS).
resource "kubernetes_network_policy_v1" "web_to_api" {
  metadata {
    name      = "web-to-api"
    namespace = local.app_ns
  }

  spec {
    pod_selector {
      match_labels = local.web_pods
    }
    policy_types = ["Egress"]

    egress {
      to {
        pod_selector {
          match_labels = local.api_pods
        }
      }
      ports {
        port     = "8000"
        protocol = "TCP"
      }
    }
  }
}

# 5. api n'accepte que web. Aucune règle de sortie pour api : hors DNS, elle ne joint rien.
resource "kubernetes_network_policy_v1" "api_from_web" {
  metadata {
    name      = "api-from-web"
    namespace = local.app_ns
  }

  spec {
    pod_selector {
      match_labels = local.api_pods
    }
    policy_types = ["Ingress"]

    ingress {
      from {
        pod_selector {
          match_labels = local.web_pods
        }
      }
      ports {
        port     = "8000"
        protocol = "TCP"
      }
    }
  }
}

# 6. Prometheus (namespace monitoring) lit les métriques de l'API, port 8000, chemin /metrics
#    (jalon 6b). Flux ajouté par la plateforme, pas par le chart : depuis le jalon 6a, nginx
#    refuse /api/metrics au public ; seules les sondes du cluster y accèdent, et seulement
#    Prometheus. Pas de règle de sortie à ajouter : c'est Prometheus qui se connecte.
resource "kubernetes_network_policy_v1" "api_from_monitoring" {
  metadata {
    name      = "api-from-monitoring"
    namespace = local.app_ns
  }

  spec {
    pod_selector {
      match_labels = local.api_pods
    }
    policy_types = ["Ingress"]

    ingress {
      from {
        namespace_selector {
          match_labels = { "kubernetes.io/metadata.name" = module.ns_monitoring.name }
        }
        pod_selector {
          match_labels = { "app.kubernetes.io/name" = "prometheus" }
        }
      }
      ports {
        port     = "8000"
        protocol = "TCP"
      }
    }
  }
}
