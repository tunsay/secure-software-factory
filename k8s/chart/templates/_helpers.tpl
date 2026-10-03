{{/*
Image d'un composant : <registre>/ssf-<composant>:<SHA>@<digest> (jalon 4).
Le digest fait foi : le contenu désigné ne peut pas changer. Le tag (SHA du commit) reste pour la
lecture humaine ; il est ignoré au tirage. Refuse un tag vide ou mobile, et une image sans digest.
Usage : {{ include "ssf.image" (list . "api") }}
*/}}
{{- define "ssf.image" -}}
{{- $root := index . 0 -}}
{{- $component := index . 1 -}}
{{- $tag := required "image.tag est obligatoire (SHA complet du commit)" $root.Values.image.tag -}}
{{- if not (regexMatch "^[0-9a-f]{40}$" $tag) -}}
{{- fail (printf "image.tag doit être un SHA de commit complet, reçu %q" $tag) -}}
{{- end -}}
{{- $digest := index $root.Values.image.digests $component | default "" -}}
{{- if not (regexMatch "^sha256:[0-9a-f]{64}$" $digest) -}}
{{- fail (printf "image.digests.%s doit être un digest sha256 (image signée publiée par la CI), reçu %q" $component $digest) -}}
{{- end -}}
{{- printf "%s/ssf-%s:%s@%s" $root.Values.image.registry $component $tag $digest -}}
{{- end -}}

{{/*
Étiquettes communes. Le sélecteur n'utilise que name + component, qui ne changent jamais :
un sélecteur de Deployment est immuable.
*/}}
{{- define "ssf.labels" -}}
{{- $root := index . 0 -}}
{{- $component := index . 1 -}}
{{ include "ssf.selectorLabels" (list $root $component) }}
app.kubernetes.io/part-of: secure-software-factory
app.kubernetes.io/version: {{ $root.Values.image.tag | trunc 12 | quote }}
app.kubernetes.io/managed-by: {{ $root.Release.Service }}
{{- end -}}

{{- define "ssf.selectorLabels" -}}
{{- $root := index . 0 -}}
{{- $component := index . 1 -}}
app.kubernetes.io/name: ssf
app.kubernetes.io/instance: {{ $root.Release.Name }}
app.kubernetes.io/component: {{ $component }}
{{- end -}}

{{/*
securityContext de pod exigé par PSS restricted : non-root, UID explicite, seccomp.
Usage : {{ include "ssf.podSecurityContext" .Values.api.uid }}
*/}}
{{- define "ssf.podSecurityContext" -}}
runAsNonRoot: true
runAsUser: {{ . }}
runAsGroup: {{ . }}
seccompProfile:
  type: RuntimeDefault
{{- end -}}

{{/*
securityContext de conteneur exigé par PSS restricted, plus le système de fichiers en lecture
seule (au-delà de PSS) : un attaquant qui prend la main ne peut pas déposer de binaire.
*/}}
{{- define "ssf.containerSecurityContext" -}}
allowPrivilegeEscalation: false
readOnlyRootFilesystem: true
capabilities:
  drop: ["ALL"]
{{- end -}}
