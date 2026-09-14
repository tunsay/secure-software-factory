# --- étape 1 : build statique -------------------------------------------------
FROM node:26-alpine AS builder

WORKDIR /build
COPY package.json package-lock.json ./
# npm ci exige un lockfile : c'est la garantie de build reproductible.
RUN npm ci --no-audit --no-fund

COPY . .
RUN npm run build

# --- étape 2 : nginx non privilégié, fichiers statiques seulement --------------
# Branche stable de nginx sur l'Alpine courant. Un tag figé (ex. 1.27-alpine) vieillit
# en quelques mois et accumule des CVE OpenSSL/musl/libxml2 déjà corrigées upstream.
FROM nginxinc/nginx-unprivileged:stable-alpine3.24 AS runtime

# Correctifs Alpine publiés depuis la dernière reconstruction de l'image officielle.
USER root
RUN apk upgrade --no-cache
USER 101

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=builder /build/dist /usr/share/nginx/html

# nginx-unprivileged tourne en UID 101 sur le port 8080.
EXPOSE 8080

HEALTHCHECK --interval=10s --timeout=3s --retries=5 CMD wget -qO- http://127.0.0.1:8080/healthz || exit 1
