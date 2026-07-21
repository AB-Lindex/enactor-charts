# enactor-charts

Helm charts for running [Enactor](https://www.enactor.co/) retail server components on
Kubernetes. The charts are published as a Helm repository via GitHub Pages and are
intended to be consumed by Kubernetes clusters, for example through ArgoCD.

> **Status:** work in progress. `enactor-pdp` is the more established chart; `enactor-em`
> is newer and being brought up to production readiness.

## Charts

| Chart | Version | What it deploys |
|-------|---------|-----------------|
| [`enactor-pdp`](charts/enactor-pdp) | 0.2.35 | Point-of-Sale **P**roduct **D**istribution **P**latform — `pdp` (processing) and `pdc` (client) servers. Instance-driven: you supply `pdp.instances` / `pdc.instances`, so one release can run many stores. Optional ArgoCD sync-wave ordering. |
| [`enactor-em`](charts/enactor-em) | 0.4.0 | Enactor **E**state **M**anager — five components plus a bundled database: `ema` (WebMaintenance UI), `emp` (processing / WebCore), `ems` (web services / axis2), `tms` (Terminal Management), `emr` (WebReports). Ships a bundled [Bitnami MariaDB](https://github.com/bitnami/charts/tree/main/bitnami/mariadb) subchart (swappable for an external DB later). |

Each Enactor component runs as a single-replica StatefulSet with a persistent app-home
volume, a matching Service and ServiceAccount, and a shared plus per-component ConfigMap.
Inter-component ordering is handled by `depends-on` init containers.

## Repository layout

```
charts/
  enactor-em/          # Estate Manager chart
    templates/         # generic, range-driven manifests (see "Chart conventions")
    tests/             # helm-unittest suites + committed __snapshot__/
    values.yaml
  enactor-pdp/         # PDP/PDC chart
docs/                  # handoff / design notes (e.g. enactor-em-remaining-work.md)
ct.yaml                # chart-testing (ct) config
.github/
  workflows/
    ci.yml             # PR validation: ct lint + helm unittest
    release.yml        # publishes charts on push to main
  ct-lintconf.yaml     # lenient yamllint rules for ct
.gitattributes         # forces LF so rendering is deterministic across OSes
```

## Using the charts

Add the published Helm repository and install:

```sh
helm repo add enactor-charts https://ab-lindex.github.io/enactor-charts/
helm repo update

# Estate Manager (bundled MariaDB) — minimal required values:
helm install em enactor-charts/enactor-em -n em --create-namespace \
  --set storage.storageClass=<class> \
  --set mariadb.primary.persistence.storageClass=<class> \
  --set dns.domain=<your.fqdn>
```

`enactor-em` requires a storage class that exists on the target cluster (enforced by
`templates/required.yaml`) and an image-pull secret for the private registry. Secrets
(`em-secrets`, `secret-common`) are referenced by name and are typically supplied as
SealedSecrets via the `extraObjects` value. See
[`docs/enactor-em-remaining-work.md`](docs/enactor-em-remaining-work.md) for install notes
and remaining work.

## Chart conventions

`enactor-em` uses **generic, range-driven templates** rather than one file per component.
`values.yaml` holds a `components:` map, and single templates
(`templates/statefulset.yaml`, `services.yaml`, `serviceaccounts.yaml`) iterate over it.
Each component entry declares only what varies:

```yaml
components:
  emr:
    stdRepo: true            # pick image.stdRepository instead of image.repository
    image: emr               # image name appended to the chosen repository root
    dependsOn: { component: emp }   # wait on emp's http port before starting
    containerPorts: [http]
    probes: { livenessProbe: {...}, readinessProbe: {...}, startupProbe: {...} }
```

To add a component, add an entry to `components:` (and the matching `network:` /
`dns:` ports) plus a `configmap-<name>.yaml` for its bespoke config — no new
StatefulSet/Service/ServiceAccount files needed.

## Development

Requirements: [Helm](https://helm.sh/) **4.x** (CI pins v4.1.4), and the
[helm-unittest](https://github.com/helm-unittest/helm-unittest) plugin v1.1.1 for tests.

```sh
# One-time: dependency repo for the MariaDB subchart
helm repo add bitnami https://charts.bitnami.com/bitnami
helm dependency build charts/enactor-em

# Lint + render
helm lint charts/enactor-em
helm template em charts/enactor-em -n em \
  --set storage.storageClass=x --set mariadb.primary.persistence.storageClass=x \
  --set dns.domain=example.test

# Unit tests (snapshot + assertions)
helm plugin install https://github.com/helm-unittest/helm-unittest --version v1.1.1 --verify=false
helm unittest --with-subchart=false charts/enactor-em
```

### Tests

`charts/enactor-em/tests/*_test.yaml` contain assertion and **snapshot** tests. The
snapshots lock the full rendered StatefulSet / Service / ServiceAccount output, so any
template change that alters rendering fails the suite until the snapshot is regenerated on
purpose:

```sh
helm unittest --with-subchart=false -u charts/enactor-em   # review the diff before committing
```

> **Line endings matter.** Rendered manifests hash their ConfigMaps into `checksum/*` pod
> annotations, so CRLF vs LF changes the output. `.gitattributes` forces **LF** for all text
> files to keep rendering (and snapshots) byte-identical on every OS. Don't disable it, and
> if you clone on Windows make sure your editor preserves LF.

## CI & releases

- **`ci.yml`** runs on every non-`main` branch push and on PRs into `main`:
  - **`ct lint`** ([chart-testing](https://github.com/helm/chart-testing)) — lints changed
    charts and **requires a chart-version bump** vs `main`. This is the guard against an
    unbumped version being silently skipped at release. yamllint runs with the lenient
    rules in `.github/ct-lintconf.yaml`.
  - **`helm unittest`** — runs the test suites above.
- **`release.yml`** runs on push to `main`: [chart-releaser](https://github.com/helm/chart-releaser-action)
  packages any chart whose version changed and publishes it to the GitHub Pages Helm repo
  at `https://ab-lindex.github.io/enactor-charts/`.

**Bump `Chart.yaml` `version:` for any chart you change** — CI enforces it, and
chart-releaser silently ignores an unchanged version (no release).

## Contributing

1. Branch off `main`.
2. Make changes; bump the affected chart's `version:`.
3. Run `helm lint` and `helm unittest` locally; regenerate snapshots (`-u`) if rendering
   changed intentionally, and review the diff.
4. Open a PR into `main` — CI must be green.
5. On merge, `release.yml` publishes the new chart version.
