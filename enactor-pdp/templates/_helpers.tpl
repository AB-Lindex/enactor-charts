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

{{- define "deviceid" -}}
pdpServer@{{ .Values.store.id }}.Enactor
{{- end }}
