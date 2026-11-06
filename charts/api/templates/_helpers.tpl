{{- define "api.name" -}}
{{- .Chart.Name -}}
{{- end -}}

{{- define "api.fullname" -}}
{{- if contains .Chart.Name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "api.selectorLabels" -}}
app.kubernetes.io/name: {{ include "api.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "api.labels" -}}
{{ include "api.selectorLabels" . }}
app.kubernetes.io/version: {{ .Values.image.tag | default .Chart.AppVersion | trunc 63 | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{- end -}}

{{- define "api.image" -}}
{{- $tag := required "image.tag é obrigatório (o CI define o valor por ambiente)" .Values.image.tag -}}
{{- printf "%s:%s" .Values.image.repository $tag -}}
{{- end -}}

{{/* Seletor PromQL comum às regras de SLO */}}
{{- define "api.sloSelector" -}}
namespace="{{ .Release.Namespace }}", service="{{ include "api.fullname" . }}", route=~"/api/.*"
{{- end -}}
