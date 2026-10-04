# --- étape 1 : build statique -------------------------------------------------
# Politique : LTS actif uniquement (Node 24 depuis oct. 2025). Dependabot propose la
# dernière version, y compris non-LTS ; les majeures non-LTS sont ignorées via commentaire PR.
# Images de base épinglées par digest (jalon 4b) : voir app/api/Dockerfile.
FROM node:24-alpine@sha256:ebfe2f90462722a7a4de65e91990e97fe0d401c70e0e762c5b53302f905ec1c1 AS builder

WORKDIR /build
COPY package.json package-lock.json ./
# npm ci exige un lockfile : c'est la garantie de build reproductible.
RUN npm ci --no-audit --no-fund

COPY . .
RUN npm run build

# --- étape 2 : nginx non privilégié, fichiers statiques seulement --------------
# Branche stable de nginx sur l'Alpine courant. Un tag figé (ex. 1.27-alpine) vieillit
# en quelques mois et accumule des CVE OpenSSL/musl/libxml2 déjà corrigées upstream.
FROM nginxinc/nginx-unprivileged:stable-alpine3.24@sha256:ed04ec1ff34502c339ee5c3ae3f855442398edc1d05591e2b98981dcbbd20b1e AS runtime

# Correctifs Alpine publiés depuis la dernière reconstruction de l'image officielle.
USER root
RUN apk upgrade --no-cache
USER 101

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY security-headers.conf /etc/nginx/snippets/security-headers.conf
COPY --from=builder /build/dist /usr/share/nginx/html

# nginx-unprivileged tourne en UID 101 sur le port 8080.
EXPOSE 8080

HEALTHCHECK --interval=10s --timeout=3s --retries=5 CMD wget -qO- http://127.0.0.1:8080/healthz || exit 1
