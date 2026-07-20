# enactor-em — remaining work

Handoff notes for continuing the enactor-em Kubernetes work in a new session.

## Where things stand

The `enactor-em` chart is now **deployable and verified running on the store-qa cluster**.
Goal was to move Enactor EM off Docker Swarm (VMs, deployed by Ansible from `Lindex.IaC`) onto
Kubernetes, starting with store-qa, eventually replacing the Swarm EM.

**Branch:** `feature/enactor-em-deployable` (2 commits, not yet merged or published)
- `9ac0468` — chart reworked to be deployable (per-component images, HTTP-only, secrets hygiene, ingress)
- `888d72a` — fixes found during the first store-qa install

**Verified on store-qa (namespace `em`, helm release `em`), 2026-07-20:**
- All 4 pods 1/1 Ready: `em-db`, `ema`, `emp`, `ems`
- Init ordering held: em-db → emp → ems → ema
- EM self-created the `enactorem` schema (764 tables) against the empty bundled MariaDB
- EMA reachable via ingress (`store-qa.lindex.to/WebMaintenance/` → 302 StartApplication) and in-cluster

## Decisions already made (don't relitigate)

| Topic | Decision |
|---|---|
| Components | `ema`, `emp`, `ems` only — no `tms`, `emr`, `emc` |
| Database | Bundled Bitnami MariaDB for now; external `lxsqlstoredb24` later, at Swarm cutover |
| Schema | EM self-creates on empty DB (confirmed); config import done manually |
| TLS | Terminated by nginx ingress controller; all in-pod/cluster traffic plain HTTP |
| Store → EM | Cross-namespace cluster DNS; ingress only for the EMA WebMaintenance UI |
| Secrets | Referenced by name; SealedSecrets via `extraObjects` (like enactor-pdp) |

## Key facts for next session

- **Registry:** `lindexacrdev.azurecr.io/commerce/enactorpos`, images `lindexextension-{ema,emp,ems}`,
  pull secret `pullsecret`. EM image tag used: `2.7.747.RC2.557.1978-20260716.2`.
  ⚠️ The old `crsdcshared.azurecr.io/pos` path is stale — running store pods already use lindexacrdev.
- **store-qa storage class:** `rwo-filesystem`. MariaDB `existingSecret: em-secrets` needs keys
  `mariadb-password`, `mariadb-root-password`, `mariadb-replication-password`.
- **EM images run as uid/gid 1100 (tomcat_admin/tomcat)** → chart sets `podSecurityContext.fsGroup: 1100`.
- **Cluster auth:** the agent's Bash reached store-qa via an OIDC kubeconfig credential
  (`olof.spetz-store-qa`). Plain kubelogin caused single-use refresh-token contention between the
  agent and the user's shell.
- **Test install artifacts (not committed):** `<scratchpad>/em-install/{values.yaml,secrets.yaml}`.
  `secrets.yaml` holds TEST-ONLY plaintext secrets (random DB password, axis2, task=taskadmin).

## Remaining work

### 1. Merge and publish the chart
- Merge `feature/enactor-em-deployable` to `main`. Pushing to `main` triggers
  `.github/workflows/release.yml` (chart-releaser) which publishes to the GitHub Pages repo
  `https://ab-lindex.github.io/enactor-charts/`.
- Chart version is already bumped to `0.2.0`. Confirm it's a fresh version chart-releaser hasn't
  seen, or bump again — an unbumped version is silently not released.

### 2. ArgoCD Application for EM (declarative delivery)
- Add an `Application` manifest to `K8s-QA-StoreInfrastructure` (pattern: `apps/9900.yaml`), pulling
  `enactor-em` from the published chart with an inline `valuesObject` (tag, storageClass
  `rwo-filesystem`, ingress, dns).
- Replace the test plaintext secrets with **SealedSecrets** injected via `extraObjects`:
  - `em-secrets` (MariaDB: mariadb-password / -root-password / -replication-password)
  - `secret-common` (ENACTOR_AXIS2_PASSWORD, ENACTOR_TASK_SYSTEMPASSWORD)
  - `pullsecret` — reuse the existing lindexacrdev docker pull secret used by the stores.
- Reconcile the registry: `apps/9900.yaml` in git still shows `crsdcshared`; the running truth is
  `lindexacrdev.azurecr.io/commerce/enactorpos`.

### 3. Point a store at the in-cluster EM
- Switch a store (e.g. 9900) from `lxconstore24.lindex.to` (Swarm EM) to the in-cluster EM via
  `estate.ema/emp/ems` cluster-DNS values (e.g. `http://ems.em.svc.cluster.local:39833`).
- Verify end-to-end (PDP ↔ EM). Watch RMI/JMX: `emp` advertises its pod IP; ema/ems point
  `ENACTOR_JMX_MANAGEMENTNODEHOSTNAME` at the `emp` ClusterIP service. If callbacks misbehave, emp
  likely needs a headless service.
- Config import: run `Lindex.IaC` `Deploy/deploy-em-config.yml` (REST import to
  `/WebRestApi/rest/configuration/import/`) against the in-cluster EMS once it's reachable.

### 4. External-DB switchover (later, at Swarm cutover)
- Add an external-DB path (`mariadb.deploy: false` + host/port values) to connect EM pods to
  `lxsqlstoredb24` instead of the bundled MariaDB, and migrate/point at the existing `enactorem`.

## Known smaller items / tech debt

- `emp` and `ems` still use httpGet probes with a tight 1s timeout (they pass because `/WebCore/`
  and `/axis2/` respond fast, but could be hardened like ema's tcpSocket probes).
- The chart was fixed in place, not refactored onto enactor-pdp's structure (three near-identical
  StatefulSet/config templates remain). A future consolidation onto PDP's conventions is possible
  but was explicitly deferred.
- `required.yaml` enforces `storage.storageClass` and `mariadb.primary.persistence.storageClass` —
  both must be set to a class that exists on the target cluster.

## Useful commands

```sh
# Render/lint locally (needs bitnami repo added once)
helm repo add bitnami https://charts.bitnami.com/bitnami
helm dependency build charts/enactor-em
helm lint charts/enactor-em
helm template em charts/enactor-em -n em -f <values>

# Current install on store-qa
kubectl -n em get pods,sts,pvc,svc,ingress
helm -n em history em
```
