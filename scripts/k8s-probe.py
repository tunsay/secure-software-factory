"""Sondes de cloisonnement, exécutées DANS le pod api (make isolation-proof).

Usage : kubectl exec -i deploy/api -- python - <sonde> [cible] < scripts/k8s-probe.py

Chaque sonde affiche OUVERT ou BLOQUÉ, puis le détail. Elle n'échoue jamais : le résultat
attendu change entre l'avant et l'après durcissement, c'est la comparaison qui fait la preuve.
Lecture seule : aucune sonde ne modifie quoi que ce soit, ni dans le pod ni dans le cluster.
"""

import json
import os
import ssl
import sys
import urllib.request

SA_DIR = "/var/run/secrets/kubernetes.io/serviceaccount/"
API_SERVER = "https://kubernetes.default.svc"


def http(url: str) -> str:
    """Le pod peut-il ouvrir une connexion HTTP vers cette cible ?"""
    with urllib.request.urlopen(url, timeout=4) as resp:
        return f"HTTP {resp.status} depuis {url}"


def token() -> str:
    """Un jeton d'identité Kubernetes est-il monté dans le pod ?"""
    if not os.path.exists(SA_DIR + "token"):
        raise FileNotFoundError(f"aucun jeton dans {SA_DIR}")
    return "jeton monté dans " + SA_DIR


def whoami() -> str:
    """Ce jeton permet-il de s'authentifier auprès de l'API Kubernetes ?"""
    with open(SA_DIR + "token", encoding="ascii") as f:
        bearer = f.read().strip()
    ctx = ssl.create_default_context(cafile=SA_DIR + "ca.crt")
    body = json.dumps({"apiVersion": "authentication.k8s.io/v1", "kind": "SelfSubjectReview"})
    req = urllib.request.Request(
        API_SERVER + "/apis/authentication.k8s.io/v1/selfsubjectreviews",
        data=body.encode(),
        headers={"Authorization": "Bearer " + bearer, "Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, context=ctx, timeout=4) as resp:
        user = json.load(resp)["status"]["userInfo"]["username"]
    return "authentifié auprès de l'API Kubernetes comme " + user


PROBES = {"http": http, "token": token, "whoami": whoami}

if __name__ == "__main__":
    name, args = sys.argv[1], sys.argv[2:]
    try:
        print("OUVERT  ", PROBES[name](*args))
    except Exception as exc:  # noqa: BLE001 — toute erreur signifie « bloqué », c'est le résultat
        print("BLOQUÉ  ", f"{type(exc).__name__}: {exc}")
