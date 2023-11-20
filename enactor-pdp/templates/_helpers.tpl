{{/*
Selector labels - pdp
*/}}
{{- define "pdp.selectorLabels" -}}
app.kubernetes.io/name: pdp
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Selector labels - pdc
*/}}
{{- define "pdc.selectorLabels" -}}
app.kubernetes.io/name: pdc
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Expand the name of the chart.
*/}}
{{- define "pdp.fullname" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Name of pdp serviceaccount.
*/}}
{{- define "pdp.serviceAccountName" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Name of pdc serviceaccount.
*/}}
{{- define "pdc.serviceAccountName" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "ems.https" -}}
https://lxconstore21.lindex.to:52243
{{- end }}

{{- define "dbserver" -}}
{{ .Release.Name }}-mariadb.{{ .Release.Namespace }}
{{- end }}

{{- define "env.defaults" -}}
{{- end }}

{{- define "env.pdp" -}}
{{- end }}

{{- define "env.pdc" -}}
{{- end }}
