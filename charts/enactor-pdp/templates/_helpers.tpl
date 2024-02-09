{{/*
Selector labels - pdp
*/}}
{{- define "pdp.selectorLabels" -}}
app.kubernetes.io/name: pdp
app.kubernetes.io/instance: {{ .id }}
{{- end }}

{{/*
Selector labels - pdc
*/}}
{{- define "pdc.selectorLabels" -}}
app.kubernetes.io/name: pdc
app.kubernetes.io/instance: {{ .id }}
{{- end }}

{{/*
Selector labels - common
*/}}
{{- define "common.selectorLabels" -}}
{{- range $key, $value := .Values.labels -}}
{{ $key }}: {{ $value | quote }}
{{ end -}}{{- end -}}

{{/*
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

{{- define "dbserver" -}}
{{ .Values.mariadb.fullnameOverride }}
{{- end }}

{{- define "mariadb.jdbc" -}}
jdbc:mysql://{{ include "dbserver" . }}:3306/{{ .Values.mariadb.auth.database }}?useSSL=false
{{- end }}

{{- define "mariadb.jdbc.quotes" -}}
jdbc:mysql:\/\/{{ include "dbserver" . }}:3306\/{{ .Values.mariadb.auth.database }}?useSSL=false
{{- end }}

{{- define "env.defaults" -}}
{{- end }}

{{- define "env.pdp" -}}
- name: ENACTOR_DB_PASS
  valueFrom:
    secretKeyRef:
      name: {{ .Values.mariadb.auth.existingSecret }}
      key: mariadb-password
{{- end }}

{{- define "env.pdc" -}}
{{- end }}


{{/*
Create image
*/}}
{{- define "image" -}}
{{ .repository }}:{{ .tag_override | default .tag | default  "latest" }}
{{- end }}


{{/*
Renders a complete tree, even values that contains template.
*/}}
{{- define "render" -}}
  {{- if typeIs "string" .value }}
    {{- tpl .value .context }}
  {{ else }}
    {{- tpl (.value | toYaml) .context }}
  {{- end }}
{{- end -}}