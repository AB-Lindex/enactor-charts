# enactor-em — add TMS and EMR components — design

**Date:** 2026-07-21
**Chart:** `charts/enactor-em`
**Branch:** `feature/enactor-em-deployable`

## Goal

Add the Terminal Management Server (**TMS**) and Estate Manager Reports (**EMR**)
components to the `enactor-em` Helm chart so the Kubernetes deployment covers the
same EM surface (minus `emc`) that the Docker Swarm / compose stack runs. Both
components are **always deployed** alongside the existing `ema`/`emp`/`ems` — no
enable/disable toggle.

Runtime configuration is derived from the compose reference in
`Lindex.EnactorPOS.DockerCompose/test/lindexextension/docker-compose-em.yml` and the
env files in `Lindex.EnactorPOS.DockerCompose/test/lindexextensionEnvs/`
(`tms.env`, `emr.env`, `common-em.env`, `common.env`).

## Decisions made (do not relitigate)

| Topic | Decision |
|---|---|
| Which components | `tms` and `emr` only — still no `emc` |
| Enablement | Always deployed (no `deploy.*` toggle), same as ema/emp/ems |
| Structure | Extend the existing near-identical per-component pattern; **no** generic-template refactor (that consolidation stays deferred) |
| Exposure | Cluster-DNS / ClusterIP only for now; ingress stays limited to EMA's WebMaintenance. Add ingress for `/WebReports/` or `/WebTerminalManager/` later if browser access is needed |
| TLS posture | HTTP-only in-cluster, matching ema/ems: override `ENACTOR_TOMCAT_HTTP_DISABLED=false`, no keystore mount, TLS terminated at ingress if/when added |
| Reporting secondary datasource | Stays disabled (`ENABLE_ENACTOR_SECONDARY_DATASOURCE=false`); no values plumbing yet (add at Swarm cutover if a reporting replica is introduced) |
| Naming | Short service names `tms` and `emr`, consistent with `ema`/`emp`/`ems` |

## Component summary

| Component | k8s name | HTTP port | Health path | Extra ports | JMX mgmt node | Depends on (init) |
|---|---|---|---|---|---|---|
| Terminal Management Server | `tms` | 39888 | `/WebTerminalManager/` | RMI 39851 | `emp` | `emp:39832` |
| Estate Manager Reports | `emr` | 39831 | `/WebReports/` | — | `emp` | `emp:39832` |

Both use `emp` as the JMX management node (per `tms.env` `ENACTOR_JMX_MANAGEMENTNODEHOSTNAME=em-processing`
and `emr` being a report node), so each `depends-on` init container waits on `emp:39832`,
exactly like `ems`/`ema` do today.

## Images

TMS/EMR live under a **different repository root** than ema/emp/ems:

- `lindexacrdev.azurecr.io/enactorstandard/lin/tms`
- `lindexacrdev.azurecr.io/enactorstandard/lin/emr`

(vs `lindexacrdev.azurecr.io/commerce/enactorpos/lindexextension-{ema,emp,ems}`).
This mirrors the compose file's `STD_REPO_PREFIX` (plain `tms`/`emr` names) vs
`POS_REPO_PREFIX` (`lindexextension-*`) split.

The chart's existing `image.repository` value is reused only for ema/emp/ems. A new
`image.stdRepository` root plus `image.tms`/`image.emr` name keys are added for the two
new components. They share the same `image.tag` and `image.pullPolicy` and the existing
`pullsecret` imagePullSecret.

## File changes

### New templates (each mirrors the existing `ems` set)
- `templates/statefulset-tms.yaml`
- `templates/statefulset-emr.yaml`
- `templates/configmap-tms.yaml`
- `templates/configmap-emr.yaml`

### Edited templates
- `templates/_helpers.tpl` — add `tms.name`/`emr.name`, `*.http.port`, labels,
  selectorLabels, and http-address helpers for both, following the ema/emp/ems blocks.
- `templates/services.yaml` — add two ClusterIP services (`tms`, `emr`) using the
  existing `service.ports` helper against `network.tms` / `network.emr`.
- `templates/serviceaccounts.yaml` — add service accounts for `tms` and `emr`.
- `templates/configmap-common.yaml` — repoint the already-present references at the new
  service DNS instead of hardcoded/localhost values:
  - `ENACTOR_SERVER_EMREPORT_HOST`, `ENACTOR_SERVER_REPORTS_HOST` → `emr` name
  - `ENACTOR_SERVER_EMREPORT_HTTPPORT`, `ENACTOR_SERVER_REPORTS_HTTPPORT` → `emr` http port
  - `ENACTOR_SERVER_EMREPORTS_URL_BASE` → `emr` http address
  - `ENACTOR_SERVER_TMS_URL_BASE` → `tms` http address (currently `http://localhost:39888`)
- `values.yaml` — image/network/dns additions (below).
- `Chart.yaml` — bump `version: 0.2.0 → 0.3.0`.

### values.yaml additions
```yaml
image:
  # ema/emp/ems continue to use the existing `repository` root.
  stdRepository: lindexacrdev.azurecr.io/enactorstandard/lin
  tms: tms
  emr: emr

network:
  tms:
    http: 39888
    rmi: 39851
  emr:
    http: 39831

dns:
  tms: tms
  emr: emr
```

## Per-component template detail

Both StatefulSets follow the `statefulset-ems.yaml` shape: single replica,
`RollingUpdate`, `automountServiceAccountToken: false`, `podSecurityContext`
(`fsGroup: 1100`), `terminationGracePeriodSeconds: 300`, a `depends-on` init container
against `emp:39832`, `db.env` + `ENACTOR_JMX_SERVERHOSTNAME`/`ENACTOR_RMI_SERVERHOST`
(podIP fieldRef) + `ENACTOR_JMX_APPLICATIONID` (metadata.name fieldRef), `envFrom`
`config-common` / `config-<name>` / `secret-common`, and a single `apphome`
`volumeClaimTemplate` using `storage.storageClass` / `storage.size`.

Image reference differs from ema/emp/ems:
`{{ printf "%s/%s" .Values.image.stdRepository .Values.image.tms | clean }}:{{ tag }}`.

### tms
- Container port `http` 39888; also expose RMI 39851 on the service.
- **Probes:** `tcpSocket` on `http` (compose defines no healthcheck for tms, so avoid
  guessing a URL) — same style as `ema`.
- `configmap-tms.yaml` data (from `tms.env`, minus RMI/JMX host which the pod sets via
  fieldRef): `ENACTOR_MODULES_TMS: "true"`, `ENACTOR_TOMCAT_HTTP_DISABLED: "false"`.

### emr
- Container port `http` 39831.
- **Probes:** `httpGet /WebReports/` on `http` (liveness/readiness/startup), like `ems`'s
  `/axis2/`.
- `configmap-emr.yaml` data (from `emr.env`): heap `JMPS: "128m"`, `JXMS: "1024m"`,
  `JXMX: "5120m"`, `ENACTOR_MAXTOTAL: "300"`, `ENACTOR_MAXTHREADS: "200"`,
  `ENACTOR_SERVICE_DEFAULTSCHEDULEDJOBRUNTIMECONTEXT: "Enactor Web Reports"`,
  `ENABLE_ENACTOR_SECONDARY_DATASOURCE: "false"`, `ENACTOR_TOMCAT_HTTP_DISABLED: "false"`.
  The secondary-datasource `REPLACE_*` values are **not** carried over (disabled; no
  reporting replica yet).

## Init / dependency ordering

Existing order holds: `em-db → emp → ems → ema`. TMS and EMR each add a `depends-on`
init container waiting on `emp:39832`, so they start once `emp` is reachable
(in parallel with / after `ems`). No new ordering constraints between tms, emr, ems, ema.

## Out of scope

- `emc` component.
- Ingress for `/WebReports/` or `/WebTerminalManager/`.
- Enabling the reporting secondary datasource / external reporting replica.
- Generic per-component template consolidation.
- The broader remaining-work items (merge/publish, ArgoCD app, store cutover, external DB)
  tracked in `docs/enactor-em-remaining-work.md`.

## Verification

- `helm lint charts/enactor-em` and `helm template em charts/enactor-em -n em -f <values>`
  render cleanly with the two new StatefulSets, ConfigMaps, and Services.
- On store-qa: `tms` and `emr` pods reach `1/1 Ready`; `emr` `/WebReports/` responds and
  `tms` `/WebTerminalManager/` port is listening; existing `ema`/`emp`/`ems` unaffected.
