# k8s/ — cluster local durci (semaines 3 et 5)

```
kind-cluster.yaml     cluster multi-nœuds
chart/                Helm chart maison : deployment, service, ingress, HPA
network-policies/     deny-by-default, puis ouverture flux par flux
policies/             Kyverno : pas de :latest, runAsNonRoot, limites, signature Cosign vérifiée
```

Cible : Pod Security Standards `restricted` sur le namespace applicatif, score kube-bench
et kubescape capturés avant/après durcissement.
