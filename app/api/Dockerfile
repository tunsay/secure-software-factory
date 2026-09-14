# --- étape 1 : build des dépendances dans un venv isolé -----------------------
FROM python:3.14-slim AS builder

ENV PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /build
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

COPY requirements.txt .
# S4 : passer à --require-hashes (pip-compile --generate-hashes) pour figer la supply chain.
RUN pip install -r requirements.txt \
 && pip uninstall -y pip setuptools wheel

# --- étape 2 : image finale, sans pip, sans compilateur, sans root ------------
FROM python:3.14-slim AS runtime

ARG APP_VERSION=0.1.0
ENV APP_VERSION=${APP_VERSION} \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/opt/venv/bin:$PATH"

# Correctifs de sécurité Debian : l'image officielle traîne derrière les avis de sécurité
# de plusieurs jours/semaines. Sans cette ligne, Trivy bloque sur des CVE déjà corrigées upstream.
RUN apt-get update \
 && apt-get upgrade -y --no-install-recommends \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

# Aucun gestionnaire de paquets Python à l'exécution : l'image ne doit jamais rien installer.
# Retire pip/setuptools livrés dans l'image de base (et leurs CVE avec).
RUN python -m pip uninstall -y pip setuptools wheel 2>/dev/null || true \
 && rm -rf /usr/local/lib/python3.*/site-packages/pip* \
           /usr/local/lib/python3.*/site-packages/setuptools* \
           /usr/local/lib/python3.*/site-packages/wheel* \
           /usr/local/lib/python3.*/ensurepip \
           /root/.cache \
 && ! python -m pip --version 2>/dev/null  # échoue le build si pip est encore là

# Utilisateur applicatif non privilégié, UID fixe (utile pour les PSS Kubernetes).
RUN groupadd --gid 10001 app && useradd --uid 10001 --gid app --no-create-home --shell /usr/sbin/nologin app

COPY --from=builder /opt/venv /opt/venv
WORKDIR /srv
COPY --chown=app:app app ./app

USER 10001:10001
EXPOSE 8000

HEALTHCHECK --interval=10s --timeout=3s --retries=5 \
  CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/health').status==200 else 1)"

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--no-server-header"]
