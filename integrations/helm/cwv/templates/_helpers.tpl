{{/*
Chart name, truncated to a DNS label.
*/}}
{{- define "cwv.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Fully qualified name. A release named "cwv" stays "cwv".
*/}}
{{- define "cwv.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{- define "cwv.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "cwv.labels" -}}
helm.sh/chart: {{ include "cwv.chart" . }}
{{ include "cwv.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "cwv.selectorLabels" -}}
app.kubernetes.io/name: {{ include "cwv.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "cwv.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "cwv.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Args for the image entrypoint `cwv`. rates and cities are Price Index commands.
*/}}
{{- define "cwv.args" -}}
- {{ .Values.command | quote }}
{{- if and (eq .Values.command "rates") .Values.city }}
- --city
- {{ .Values.city | quote }}
{{- end }}
{{- if and (eq .Values.command "rates") .Values.products }}
- --product
- {{ join "," .Values.products | quote }}
{{- end }}
{{- if .Values.country }}
- --country
- {{ .Values.country | quote }}
{{- end }}
{{- if .Values.currency }}
- --currency
- {{ .Values.currency | quote }}
{{- end }}
- --format
- {{ .Values.format | quote }}
- --locale
- {{ .Values.locale | quote }}
{{- if .Values.noColor }}
- --no-color
{{- end }}
{{- if .Values.apiUrl }}
- --api-url
- {{ .Values.apiUrl | quote }}
{{- end }}
{{- range .Values.extraArgs }}
- {{ . | quote }}
{{- end }}
{{- end }}
