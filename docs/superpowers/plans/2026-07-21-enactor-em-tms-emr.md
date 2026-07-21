# Add TMS and EMR to enactor-em — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the Terminal Management Server (`tms`) and Estate Manager Reports (`emr`) components to the `enactor-em` Helm chart as always-deployed members alongside `ema`/`emp`/`ems`.

**Architecture:** Extend the existing near-identical per-component pattern (one StatefulSet + one ConfigMap + one Service + one ServiceAccount per component, wired through shared helpers). No generic-template refactor. TMS/EMR pull from a different registry root than ema/emp/ems and run HTTP-only in-cluster (TLS terminated at ingress if/when added).

**Tech Stack:** Helm 3, Kubernetes StatefulSets/Services/ConfigMaps, Bitnami MariaDB subchart.

**Spec:** `docs/superpowers/specs/2026-07-21-enactor-em-tms-emr-design.md`

## Global Constraints

- Chart path: `charts/enactor-em`. All template paths below are relative to `charts/enactor-em/templates/`.
- New component k8s names: `tms` and `emr` (short, lowercase).
- TMS/EMR image root: `lindexacrdev.azurecr.io/enactorstandard/lin`, image names `tms` / `emr`. This is a **different root** from ema/emp/ems (`lindexacrdev.azurecr.io/commerce/enactorpos` + `lindexextension-*`); do not reuse `image.repository` for them.
- HTTP-only in-cluster: both components set `ENACTOR_TOMCAT_HTTP_DISABLED: "false"` and mount **no** keystore.
- Ports: `tms` http `39888`, tms rmi `39851`; `emr` http `39831`.
- Health paths: `tms` → `/WebTerminalManager/` (but use a **tcpSocket** probe — no compose healthcheck exists), `emr` → `/WebReports/` (httpGet probe).
- Both depend on `emp:39832` via the `depends-on` init container.
- Commit messages: **no `Co-Authored-By` trailer** (user preference).
- Work stays on branch `feature/enactor-em-deployable` — do NOT create a new branch.

## Render-test command (used by every task)

`required.yaml` fails the render unless two storage classes are set, so all render checks use:

```bash
helm template em charts/enactor-em -n em \
  --set storage.storageClass=standard \
  --set mariadb.primary.persistence.storageClass=standard
```

This is referred to below as **`RENDER`**. Define it as a shell function once per session so the `RENDER | grep ...` steps work verbatim (functions pipe cleanly; aliases do not in non-interactive shells):

```bash
cd C:/Users/l19562234/Development/Repos/enactor-charts
helm repo add bitnami https://charts.bitnami.com/bitnami   # ok if already added
helm dependency build charts/enactor-em                    # ensures the mariadb subchart is present
RENDER() { helm template em charts/enactor-em -n em \
  --set storage.storageClass=standard \
  --set mariadb.primary.persistence.storageClass=standard; }
```

## File structure

- `charts/enactor-em/values.yaml` — add `image.stdRepository`/`image.tms`/`image.emr`, `network.tms`/`network.emr`, `dns.tms`/`dns.emr`.
- `charts/enactor-em/Chart.yaml` — version bump `0.2.0 → 0.3.0`.
- `charts/enactor-em/templates/_helpers.tpl` — name/port/http-address/labels/selectorLabels for `tms` and `emr`.
- `charts/enactor-em/templates/services.yaml` — add `tms` and `emr` Services.
- `charts/enactor-em/templates/serviceaccounts.yaml` — add `tms` and `emr` ServiceAccounts.
- `charts/enactor-em/templates/configmap-tms.yaml` — NEW.
- `charts/enactor-em/templates/statefulset-tms.yaml` — NEW.
- `charts/enactor-em/templates/configmap-emr.yaml` — NEW.
- `charts/enactor-em/templates/statefulset-emr.yaml` — NEW.
- `charts/enactor-em/templates/configmap-common.yaml` — repoint EMREPORT/REPORTS/TMS references at the new service DNS.

---

### Task 1: Values and chart version

**Files:**
- Modify: `charts/enactor-em/values.yaml`
- Modify: `charts/enactor-em/Chart.yaml`

**Interfaces:**
- Produces: `.Values.image.stdRepository`, `.Values.image.tms`, `.Values.image.emr`, `.Values.network.tms.{http,rmi}`, `.Values.network.emr.http`, `.Values.dns.tms`, `.Values.dns.emr`. Consumed by every later task.

- [ ] **Step 1: Add image keys.** In `values.yaml`, under the `image:` block, after the `ems: lindexextension-ems` line, add:

```yaml
  # TMS/EMR live under a different registry root than ema/emp/ems.
  stdRepository: lindexacrdev.azurecr.io/enactorstandard/lin
  tms: tms
  emr: emr
```

- [ ] **Step 2: Add network keys.** In `values.yaml`, under `network:`, after the `ems:` block, add:

```yaml
  tms:
    http: 39888
    rmi: 39851
  emr:
    http: 39831
```

- [ ] **Step 3: Add dns keys.** In `values.yaml`, under `dns:`, after the `emp: emp` line, add:

```yaml
  tms: tms
  emr: emr
```

- [ ] **Step 4: Bump chart version.** In `Chart.yaml`, change `version: 0.2.0` to `version: 0.3.0`.

- [ ] **Step 5: Verify the chart still renders and lints.**

```bash
helm lint charts/enactor-em
RENDER >/dev/null && echo "RENDER OK"
```
Expected: lint reports `0 chart(s) failed`; `RENDER OK` prints (existing ema/emp/ems still render — no new objects yet).

- [ ] **Step 6: Commit.**

```bash
git add charts/enactor-em/values.yaml charts/enactor-em/Chart.yaml
git commit -m "Add tms/emr image, network, dns values and bump chart to 0.3.0"
```

---

### Task 2: Helpers, Services, ServiceAccounts for tms and emr

**Files:**
- Modify: `charts/enactor-em/templates/_helpers.tpl`
- Modify: `charts/enactor-em/templates/services.yaml`
- Modify: `charts/enactor-em/templates/serviceaccounts.yaml`

**Interfaces:**
- Consumes: values from Task 1.
- Produces: template helpers `tms.name`, `emr.name`, `tms.http.port`, `emr.http.port`, `tms.http`, `emr.http`, `tms.labels`, `emr.labels`, `tms.selectorLabels`, `emr.selectorLabels`. Consumed by Tasks 3–5.

- [ ] **Step 1: Add name/port/address helpers.** In `_helpers.tpl`, after the `emp.http` definition (the block ending around line 69, before `Expand the name of the chart`), insert:

```gotemplate
{{/*
TMS name
*/}}
{{- define "tms.name" -}}
tms
{{- end }}

{{/*
EMR name
*/}}
{{- define "emr.name" -}}
emr
{{- end }}

{{/*
TMS - http-port
*/}}
{{- define "tms.http.port" -}}
{{ .Values.network.tms.http }}
{{- end }}

{{/*
EMR - http-port
*/}}
{{- define "emr.http.port" -}}
{{ .Values.network.emr.http }}
{{- end }}

{{/*
TMS - http-address
*/}}
{{- define "tms.http" -}}
http://{{ include "tms.name" . }}:{{ include "tms.http.port" . }}
{{- end }}

{{/*
EMR - http-address
*/}}
{{- define "emr.http" -}}
http://{{ include "emr.name" . }}:{{ include "emr.http.port" . }}
{{- end }}
```

- [ ] **Step 2: Add labels helpers.** In `_helpers.tpl`, after the `ems.labels` definition (around line 149), insert:

```gotemplate
{{/*
tms - labels
*/}}
{{- define "tms.labels" -}}
helm.sh/chart: {{ include "enactor-em.chart" . }}
{{ include "tms.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
emr - labels
*/}}
{{- define "emr.labels" -}}
helm.sh/chart: {{ include "enactor-em.chart" . }}
{{ include "emr.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}
```

- [ ] **Step 3: Add selectorLabels helpers.** In `_helpers.tpl`, after the `ems.selectorLabels` definition (around line 174), insert:

```gotemplate
{{/*
Selector labels - tms
*/}}
{{- define "tms.selectorLabels" -}}
app.kubernetes.io/name: {{ include "tms.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Selector labels - emr
*/}}
{{- define "emr.selectorLabels" -}}
app.kubernetes.io/name: {{ include "emr.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
```

- [ ] **Step 4: Add Services.** In `services.yaml`, at the end of the file (after the `ems` Service block), append:

```gotemplate
---
apiVersion: v1
kind: Service
metadata:
  name: {{ include "tms.name" . }}
  labels:
    {{- include "tms.labels" . | nindent 4 }}
spec:
  type: {{ .Values.service.type }}
  ports:
    {{- include "service.ports" .Values.network.tms | nindent 4 }}
  selector:
    {{- include "tms.selectorLabels" . | nindent 4 }}
---
apiVersion: v1
kind: Service
metadata:
  name: {{ include "emr.name" . }}
  labels:
    {{- include "emr.labels" . | nindent 4 }}
spec:
  type: {{ .Values.service.type }}
  ports:
    {{- include "service.ports" .Values.network.emr | nindent 4 }}
  selector:
    {{- include "emr.selectorLabels" . | nindent 4 }}
```

- [ ] **Step 5: Add ServiceAccounts.** In `serviceaccounts.yaml`, insert two blocks immediately **before** the final `{{- end }}` line (which closes the `if .Values.serviceAccount.create`):

```gotemplate
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ include "tms.name" . }}
  labels:
    {{- include "tms.labels" . | nindent 4 }}
  {{- with .Values.serviceAccount.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
automountServiceAccountToken: false
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ include "emr.name" . }}
  labels:
    {{- include "emr.labels" . | nindent 4 }}
  {{- with .Values.serviceAccount.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
automountServiceAccountToken: false
```

- [ ] **Step 6: Verify Services and ServiceAccounts render.**

```bash
helm lint charts/enactor-em
RENDER | grep -E "name: tms|name: emr" | sort -u
RENDER | grep -E "port: 39888|targetPort: rmi|port: 39831"
```
Expected: lint passes; the grep shows `name: tms` and `name: emr`; the port grep shows `port: 39888`, `targetPort: rmi`, and `port: 39831`.

- [ ] **Step 7: Commit.**

```bash
git add charts/enactor-em/templates/_helpers.tpl charts/enactor-em/templates/services.yaml charts/enactor-em/templates/serviceaccounts.yaml
git commit -m "Add helpers, Services and ServiceAccounts for tms and emr"
```

---

### Task 3: TMS ConfigMap and StatefulSet

**Files:**
- Create: `charts/enactor-em/templates/configmap-tms.yaml`
- Create: `charts/enactor-em/templates/statefulset-tms.yaml`

**Interfaces:**
- Consumes: helpers from Task 2; `image.stdRepository`/`image.tms`, `network.tms` from Task 1; existing `dependsOn`, `db.env`, `service.ports`, `podSecurityContext`, `storage.*`.
- Produces: ConfigMap `config-tms`, StatefulSet `tms`.

- [ ] **Step 1: Create the TMS ConfigMap.** Write `configmap-tms.yaml`:

```gotemplate
apiVersion: v1
kind: ConfigMap
metadata:
  name: config-{{ include "tms.name" . }}
  labels:
    {{- include "tms.labels" . | nindent 4 }}
data:
#  ENACTOR_JMX_APPLICATIONID: "TmsServer"
  ENACTOR_JMX_MANAGEMENTNODEHOSTNAME: {{ include "emp.name" . }}
  ENACTOR_MODULES_TMS: "true"
  ENACTOR_TOMCAT_HTTP_DISABLED: "false"
  JXMX: "768m"
```

- [ ] **Step 2: Create the TMS StatefulSet.** Write `statefulset-tms.yaml`:

```gotemplate
{{ $image := printf "%s/%s" .Values.image.stdRepository .Values.image.tms | clean }}
{{ $name := include "tms.name" . }}
{{ $dependency := dict "dependsOn" .Values.global.dependsOn "service" (include "emp.name" .) "port" (include "emp.http.port" .) }}
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: {{ include "tms.name" . }}
  labels:
    {{- include "tms.labels" . | nindent 4 }}
spec:
  replicas: 1
  selector:
    matchLabels:
      {{- include "tms.selectorLabels" . | nindent 6 }}
  serviceName: {{ include "tms.name" . }}
  updateStrategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1
  template:
    metadata:
      annotations:
        checksum/common: {{ include (print $.Template.BasePath "/configmap-common.yaml") . | sha256sum }}
        checksum/tms: {{ include (print $.Template.BasePath "/configmap-tms.yaml") . | sha256sum }}
        {{- with .Values.podAnnotations }}
        {{- toYaml . | nindent 8 }}
        {{- end }}
      labels:
        {{- include "tms.selectorLabels" . | nindent 8 }}
    spec:
      automountServiceAccountToken: false
      {{- with .Values.imagePullSecrets }}
      imagePullSecrets:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      serviceAccountName: {{ include "tms.name" . }}
      securityContext:
        {{- toYaml .Values.podSecurityContext | nindent 8 }}
      terminationGracePeriodSeconds: 300

      initContainers:
        {{ include "dependsOn" $dependency | nindent 8 }}

      containers:
        - name: tms
          securityContext:
            {{- toYaml .Values.securityContext | nindent 12 }}
          image: "{{ $image }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          env:
            {{ include "db.env" . | nindent 12 }}

            - name: ENACTOR_JMX_SERVERHOSTNAME
              valueFrom:
                fieldRef:
                  fieldPath: status.podIP

            - name: ENACTOR_RMI_SERVERHOST
              valueFrom:
                fieldRef:
                  fieldPath: status.podIP

            - name: ENACTOR_JMX_APPLICATIONID
              valueFrom:
                fieldRef:
                  fieldPath: metadata.name

          envFrom:
            - configMapRef:
                name: config-common
            - configMapRef:
                name: config-{{ include "tms.name" . }}
            - secretRef:
                name: secret-common
          ports:
            - name: http
              containerPort: 39888
              protocol: TCP
            - name: rmi
              containerPort: 39851
              protocol: TCP
          # TMS has no healthcheck in the compose reference, so check the port
          # is listening rather than guess a working URL (as ema does).
          livenessProbe:
            tcpSocket:
              port: http
            timeoutSeconds: 5
            periodSeconds: 15
            failureThreshold: 5
          readinessProbe:
            tcpSocket:
              port: http
            timeoutSeconds: 5
            periodSeconds: 15
            failureThreshold: 5
          startupProbe:
            tcpSocket:
              port: http
            periodSeconds: 10
            failureThreshold: 30
            initialDelaySeconds: 20
          resources:
            {{- toYaml .Values.resources | nindent 12 }}

          volumeMounts:
            - name: apphome
              mountPath: /enactor/app/home

      {{- with .Values.nodeSelector }}
      nodeSelector:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.affinity }}
      affinity:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.tolerations }}
      tolerations:
        {{- toYaml . | nindent 8 }}
      {{- end }}
  volumeClaimTemplates:
    - metadata:
        name: apphome
      spec:
        storageClassName: {{ .Values.storage.storageClass }}
        accessModes: [ "ReadWriteOnce" ]
        resources:
          requests:
            storage: {{ .Values.storage.size }}
```

- [ ] **Step 3: Verify the TMS objects render.**

```bash
helm lint charts/enactor-em
RENDER | grep -E "enactorstandard/lin/tms|ENACTOR_MODULES_TMS|containerPort: 39888|containerPort: 39851"
```
Expected: lint passes; grep shows the `.../enactorstandard/lin/tms` image, `ENACTOR_MODULES_TMS`, and both container ports.

- [ ] **Step 4: Confirm the depends-on init container targets emp.**

```bash
RENDER | awk '/kind: StatefulSet/{s=0} /name: tms$/{s=1} s&&/value: emp/{print "tms depends-on emp OK"}'
```
Expected: prints `tms depends-on emp OK`.

- [ ] **Step 5: Commit.**

```bash
git add charts/enactor-em/templates/configmap-tms.yaml charts/enactor-em/templates/statefulset-tms.yaml
git commit -m "Add tms StatefulSet and ConfigMap"
```

---

### Task 4: EMR ConfigMap and StatefulSet

**Files:**
- Create: `charts/enactor-em/templates/configmap-emr.yaml`
- Create: `charts/enactor-em/templates/statefulset-emr.yaml`

**Interfaces:**
- Consumes: helpers from Task 2; `image.stdRepository`/`image.emr`, `network.emr` from Task 1; existing `dependsOn`, `db.env`, `podSecurityContext`, `storage.*`.
- Produces: ConfigMap `config-emr`, StatefulSet `emr`.

- [ ] **Step 1: Create the EMR ConfigMap.** Write `configmap-emr.yaml` (values from `emr.env`; secondary datasource disabled, no `REPLACE_*` carried over):

```gotemplate
apiVersion: v1
kind: ConfigMap
metadata:
  name: config-{{ include "emr.name" . }}
  labels:
    {{- include "emr.labels" . | nindent 4 }}
data:
#  ENACTOR_JMX_APPLICATIONID: "ReportServer"
  ENACTOR_JMX_MANAGEMENTNODEHOSTNAME: {{ include "emp.name" . }}
  ENACTOR_SERVICE_DEFAULTSCHEDULEDJOBRUNTIMECONTEXT: "Enactor Web Reports"
  ENACTOR_TOMCAT_HTTP_DISABLED: "false"
  ENABLE_ENACTOR_SECONDARY_DATASOURCE: "false"
  ENACTOR_MAXTOTAL: "300"
  ENACTOR_MAXTHREADS: "200"
  JMPS: "128m"
  JXMS: "1024m"
  JXMX: "5120m"
```

- [ ] **Step 2: Create the EMR StatefulSet.** Write `statefulset-emr.yaml`:

```gotemplate
{{ $image := printf "%s/%s" .Values.image.stdRepository .Values.image.emr | clean }}
{{ $name := include "emr.name" . }}
{{ $dependency := dict "dependsOn" .Values.global.dependsOn "service" (include "emp.name" .) "port" (include "emp.http.port" .) }}
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: {{ include "emr.name" . }}
  labels:
    {{- include "emr.labels" . | nindent 4 }}
spec:
  replicas: 1
  selector:
    matchLabels:
      {{- include "emr.selectorLabels" . | nindent 6 }}
  serviceName: {{ include "emr.name" . }}
  updateStrategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1
  template:
    metadata:
      annotations:
        checksum/common: {{ include (print $.Template.BasePath "/configmap-common.yaml") . | sha256sum }}
        checksum/emr: {{ include (print $.Template.BasePath "/configmap-emr.yaml") . | sha256sum }}
        {{- with .Values.podAnnotations }}
        {{- toYaml . | nindent 8 }}
        {{- end }}
      labels:
        {{- include "emr.selectorLabels" . | nindent 8 }}
    spec:
      automountServiceAccountToken: false
      {{- with .Values.imagePullSecrets }}
      imagePullSecrets:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      serviceAccountName: {{ include "emr.name" . }}
      securityContext:
        {{- toYaml .Values.podSecurityContext | nindent 8 }}
      terminationGracePeriodSeconds: 300

      initContainers:
        {{ include "dependsOn" $dependency | nindent 8 }}

      containers:
        - name: emr
          securityContext:
            {{- toYaml .Values.securityContext | nindent 12 }}
          image: "{{ $image }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          env:
            {{ include "db.env" . | nindent 12 }}

            - name: ENACTOR_JMX_SERVERHOSTNAME
              valueFrom:
                fieldRef:
                  fieldPath: status.podIP

            - name: ENACTOR_RMI_SERVERHOST
              valueFrom:
                fieldRef:
                  fieldPath: status.podIP

            - name: ENACTOR_JMX_APPLICATIONID
              valueFrom:
                fieldRef:
                  fieldPath: metadata.name

          envFrom:
            - configMapRef:
                name: config-common
            - configMapRef:
                name: config-{{ include "emr.name" . }}
            - secretRef:
                name: secret-common
          ports:
            - name: http
              containerPort: 39831
              protocol: TCP
          livenessProbe:
            httpGet:
              path: /WebReports/
              port: http
          readinessProbe:
            httpGet:
              path: /WebReports/
              port: http
          startupProbe:
            httpGet:
              path: /WebReports/
              port: http
            periodSeconds: 20
            failureThreshold: 10
            initialDelaySeconds: 20
          resources:
            {{- toYaml .Values.resources | nindent 12 }}

          volumeMounts:
            - name: apphome
              mountPath: /enactor/app/home

      {{- with .Values.nodeSelector }}
      nodeSelector:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.affinity }}
      affinity:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.tolerations }}
      tolerations:
        {{- toYaml . | nindent 8 }}
      {{- end }}
  volumeClaimTemplates:
    - metadata:
        name: apphome
      spec:
        storageClassName: {{ .Values.storage.storageClass }}
        accessModes: [ "ReadWriteOnce" ]
        resources:
          requests:
            storage: {{ .Values.storage.size }}
```

- [ ] **Step 3: Verify the EMR objects render.**

```bash
helm lint charts/enactor-em
RENDER | grep -E "enactorstandard/lin/emr|/WebReports/|containerPort: 39831|JXMX|Enactor Web Reports"
```
Expected: lint passes; grep shows the `.../enactorstandard/lin/emr` image, `/WebReports/` probe path, container port 39831, a `JXMX` line, and the `Enactor Web Reports` job runtime context.

- [ ] **Step 4: Confirm the depends-on init container targets emp.**

```bash
RENDER | awk '/kind: StatefulSet/{s=0} /name: emr$/{s=1} s&&/value: emp/{print "emr depends-on emp OK"}'
```
Expected: prints `emr depends-on emp OK`.

- [ ] **Step 5: Commit.**

```bash
git add charts/enactor-em/templates/configmap-emr.yaml charts/enactor-em/templates/statefulset-emr.yaml
git commit -m "Add emr StatefulSet and ConfigMap"
```

---

### Task 5: Repoint common configmap references to the new services

**Files:**
- Modify: `charts/enactor-em/templates/configmap-common.yaml`

**Interfaces:**
- Consumes: `emr.name`/`emr.http.port`/`emr.http` and `tms.http` helpers from Task 2.

The common configmap currently hardcodes `em-reports`/`39831` for reports and `http://localhost:39888` for TMS. Repoint them at the in-cluster service DNS.

- [ ] **Step 1: Repoint the EMREPORT host/port.** In `configmap-common.yaml`, replace:

```yaml
  ENACTOR_SERVER_EMREPORT_HOST: em-reports
  ENACTOR_SERVER_EMREPORT_HTTPPORT: "39831"
```
with:
```gotemplate
  ENACTOR_SERVER_EMREPORT_HOST: {{ include "emr.name" . }}
  ENACTOR_SERVER_EMREPORT_HTTPPORT: {{ include "emr.http.port" . | quote }}
```

- [ ] **Step 2: Repoint the EMREPORTS URL base.** Replace:

```yaml
  ENACTOR_SERVER_EMREPORTS_URL_BASE: http://em-reports:39831
```
with:
```gotemplate
  ENACTOR_SERVER_EMREPORTS_URL_BASE: {{ include "emr.http" . }}
```

- [ ] **Step 3: Repoint the REPORTS host/port.** Replace:

```yaml
  ENACTOR_SERVER_REPORTS_HOST: em-reports
  ENACTOR_SERVER_REPORTS_HTTPPORT: "39831"
```
with:
```gotemplate
  ENACTOR_SERVER_REPORTS_HOST: {{ include "emr.name" . }}
  ENACTOR_SERVER_REPORTS_HTTPPORT: {{ include "emr.http.port" . | quote }}
```

- [ ] **Step 4: Repoint the TMS URL base.** Replace:

```yaml
  ENACTOR_SERVER_TMS_URL_BASE: http://localhost:39888
```
with:
```gotemplate
  ENACTOR_SERVER_TMS_URL_BASE: {{ include "tms.http" . }}
```

- [ ] **Step 5: Verify the repointed values render.**

```bash
helm lint charts/enactor-em
RENDER | grep -E "ENACTOR_SERVER_EMREPORT_HOST: emr|ENACTOR_SERVER_EMREPORTS_URL_BASE: http://emr:39831|ENACTOR_SERVER_REPORTS_HOST: emr|ENACTOR_SERVER_TMS_URL_BASE: http://tms:39888"
```
Expected: grep shows all four repointed values (`emr`/`http://emr:39831` and `http://tms:39888`); no remaining `em-reports` or `localhost:39888`.

- [ ] **Step 6: Confirm nothing still points at the old names.**

```bash
RENDER | grep -E "em-reports|localhost:39888" && echo "STALE REFERENCE FOUND" || echo "no stale refs"
```
Expected: prints `no stale refs`.

- [ ] **Step 7: Commit.**

```bash
git add charts/enactor-em/templates/configmap-common.yaml
git commit -m "Point common EM config at in-cluster emr and tms services"
```

---

## Final verification (after all tasks)

- [ ] **Full render sanity.** All five StatefulSets present:

```bash
RENDER | grep -E "^  name: (ema|emp|ems|tms|emr)$" | sort -u
```
Expected: `ema`, `emp`, `ems`, `tms`, `emr` all listed.

- [ ] **Lint clean.**

```bash
helm lint charts/enactor-em
```
Expected: `1 chart(s) linted, 0 chart(s) failed`.

## Deferred to live-cluster testing (not part of this plan)

Deploying to store-qa and confirming `tms`/`emr` pods reach `1/1 Ready`, `/WebReports/` responds, and the `tms` port listens — done during the separate install/verify step, using the OIDC kubeconfig credential (`olof.spetz-store-qa`). Requires the real image tag and that both images exist at `lindexacrdev.azurecr.io/enactorstandard/lin/{tms,emr}`.

## Self-review notes

- Spec §2 file list — all covered (Tasks 1–5).
- Spec §3 values additions — Task 1.
- Spec §4 HTTP-only/no keystore/secondary datasource disabled — Tasks 3 (tms configmap), 4 (emr configmap); no keystore volume in either StatefulSet.
- Spec §5 probes — tms tcpSocket (Task 3), emr httpGet /WebReports/ (Task 4).
- Spec §6 version bump — Task 1.
- Helper names used in Tasks 3–5 (`tms.name`, `emr.name`, `emr.http.port`, `emr.http`, `tms.http`) all defined in Task 2.
