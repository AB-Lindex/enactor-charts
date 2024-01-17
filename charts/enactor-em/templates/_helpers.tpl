{{/*
EM-Application name
*/}}
{{- define "ema.name" -}}
ema
{{- end }}

{{/*
EM Service-name
*/}}
{{- define "ems.name" -}}
ems
{{- end }}

{{/*
EM Processing-name
*/}}
{{- define "emp.name" -}}
emp
{{- end }}

{{/*
EM-Application - http-port
*/}}
{{- define "ema.http.port" -}}
{{ .Values.network.ema.http }}
{{- end }}

{{/*
EM Service - http-port
*/}}
{{- define "ems.http.port" -}}
{{ .Values.network.ems.http }}
{{- end }}

{{/*
EM Processing - http-port
*/}}
{{- define "emp.http.port" -}}
{{ .Values.network.emp.http }}
{{- end }}

{{/*
EM Processing / JMX/RMI - port
*/}}
{{- define "jmx.port" -}}
{{ .Values.network.emp.jmx }}
{{- end }}

{{/*
EM-Application - http-address
*/}}
{{- define "ema.http" -}}
http://{{ include "ema.name" . }}:{{ include "ema.http.port" . }}
{{- end }}

{{/*
EM Service - http-address
*/}}
{{- define "ems.http" -}}
http://{{ include "ems.name" . }}:{{ include "ems.http.port" . }}
{{- end }}

{{/*
EM Processing - http-address
*/}}
{{- define "emp.http" -}}
http://{{ include "emp.name" . }}:{{ include "emp.http.port" . }}
{{- end }}


{{/*
Expand the name of the chart.
*/}}
{{- define "enactor-em.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "enactor-em.fullname" -}}
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

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "enactor-em.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "common.labels" -}}
helm.sh/chart: {{ include "enactor-em.chart" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
ema - labels
*/}}
{{- define "ema.labels" -}}
helm.sh/chart: {{ include "enactor-em.chart" . }}
{{ include "ema.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
emp - labels
*/}}
{{- define "emp.labels" -}}
helm.sh/chart: {{ include "enactor-em.chart" . }}
{{ include "emp.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
ems - labels
*/}}
{{- define "ems.labels" -}}
helm.sh/chart: {{ include "enactor-em.chart" . }}
{{ include "ems.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}


{{/*
Selector labels - ema
*/}}
{{- define "ema.selectorLabels" -}}
app.kubernetes.io/name: {{ include "ema.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Selector labels - emp
*/}}
{{- define "emp.selectorLabels" -}}
app.kubernetes.io/name: {{ include "emp.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Selector labels - ems
*/}}
{{- define "ems.selectorLabels" -}}
app.kubernetes.io/name: {{ include "ems.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
the Depends-On init-container
*/}}
{{- define "dependsOn" -}}
{{- $dependsOnImage := .dependsOn.image | default "busybox" -}}
{{- $dependsOnTag := .dependsOn.tag | default "1" -}}
{{- $dependsOnPullPolicy := .dependsOn.imagePullPolicy | default "IfNotPresent" -}}
{{- $dependsOn := (printf "%s:%s" $dependsOnImage $dependsOnTag) -}}
- name: depends-on
  image: {{ $dependsOn }}
  imagePullPolicy: {{ $dependsOnPullPolicy }}
  command:
    {{ .dependsOn.command | toYaml | indent 4 | trim }}
  securityContext:
    {{- toYaml .dependsOn.securityContext | nindent 4 }}
  resources:
    {{ .dependsOn.resources| toYaml | indent 4 | trim}}
  env:
    - name: HOST
      value: {{ .service }}
    - name: PORT
      value: {{ .port | quote}}
    - name: INTERVAL
      value: '2'
{{- end }}

{{- define "service.ports" -}}
{{- range $name, $port := . }}
- port: {{ $port }}
  targetPort: {{ $name }}
  protocol: TCP
  name: {{ $name }}
{{- end }}
{{- end }}

{{- define "jdbc" -}}
jdbc:mysql://{{ .Values.mariadb.fullnameOverride }}:3306/{{ .Values.mariadb.auth.database }}?useSSL=false
{{- end }}

{{- define "db.env" -}}
- name: ENACTOR_DB_USER
  value: enactor
- name: ENACTOR_DB_PASS
  valueFrom:
    secretKeyRef:
      name: em-secrets
      key: mariadb-password
{{- end }}


{{- define "primary.ingress" -}}
{{- range .Values.ingress.hosts -}}
{{- .host -}}
{{- end -}}
{{- end }}