# cwv-helm

Helm chart for the [`cwv`](https://github.com/coworkingview/flex-office-data/tree/main/rust) command-line tool. It installs a CronJob that runs the published image [`docker.io/coworkingview/cwv:0.1.0`](https://hub.docker.com/r/coworkingview/cwv) and prints [CoworkingView Price Index](https://coworkingview.com/en/tools/price-index) rates to the job log.

The chart name is `cwv-helm`, not `cwv`. The OCI repository is `docker.io/coworkingview/cwv-helm`. That is a different Docker Hub repository from the `coworkingview/cwv` image, so a chart tag cannot replace image tag `0.1.0`.

The image is the one built from [`rust/Dockerfile`](https://github.com/coworkingview/flex-office-data/blob/main/rust/Dockerfile) and published on Docker Hub as `coworkingview/cwv`. Tags `0.1.0` and `latest` are the same multi-arch index (`linux/amd64` and `linux/arm64`). The chart pins `0.1.0`. The image is `FROM scratch`: one static binary, entrypoint `cwv`, user `65534:65534`. There is no shell. TLS is rustls with bundled roots, so the pod does not need a CA bundle.

`cwv` reads `https://api.coworkingview.com`. No API key. The default command is `rates` (one row per city and product). `cities` is the other Price Index command. The chart does not run catalogue search.

## Install

Requires Kubernetes 1.23 or newer (CronJob `batch/v1` and `ttlSecondsAfterFinished`) and Helm 3.

From this directory, before the chart is in a registry:

```sh
helm install cwv-helm .
```

From the OCI registry this repository publishes on a `helm-v*` tag:

```sh
helm install cwv-helm oci://registry-1.docker.io/coworkingview/cwv-helm --version 0.1.1
```

Berlin only, CSV:

```sh
helm install cwv-helm oci://registry-1.docker.io/coworkingview/cwv-helm --version 0.1.1 \
  --set city=berlin --set format=csv
```

One run, without waiting for the schedule:

```sh
kubectl create job --from=cronjob/cwv-helm cwv-helm-once
kubectl logs job/cwv-helm-once
```

## Configuration

| Value | Default | |
|---|---|---|
| `image.repository` | `docker.io/coworkingview/cwv` | Published image |
| `image.tag` | `0.1.0` | Pinned tag of that image |
| `command` | `rates` | `rates` or `cities` |
| `city` | `""` | City slug, `rates` only. Empty is every city |
| `country` | `""` | ISO code, for example `DE` |
| `currency` | `""` | `EUR`, `GBP`, `USD`, `CHF`, `AED`, or any other three-letter code |
| `products` | `[]` | `rates` only. `flex_desk`, `fix_desk`, `private_office`, `exclusive_bereich`, `day_pass`, `meeting_room`, `event_space`, `virtual_office`, `membership` |
| `format` | `json` | `table`, `csv`, or `json` |
| `locale` | `en` | `en`, `es`, or `de` |
| `noColor` | `true` | Passes `--no-color` |
| `apiUrl` | `""` | Passed as `--api-url` when set. CLI default is `https://api.coworkingview.com` |
| `schedule` | `0 6 * * *` | Cron expression, UTC |
| `concurrencyPolicy` | `Forbid` | |
| `resources.limits.memory` | `128Mi` | |

The container runs as uid/gid 65534 with a read-only root filesystem, no privilege escalation, and all capabilities dropped. The service account token is not mounted.

## Output and attribution

The job log is the CLI output. With `format: json` the object contains `attribution`, `license`, and `as_of`. With `table` or `csv` the attribution is on stderr.

Price Index data (`rates`, `cities`) is [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Credit *CoworkingView Price Index* and link to <https://coworkingview.com/en/tools/price-index>. Keep the attribution the CLI prints with any figure you republish.

## Licence

The chart and the `cwv` code are [MIT](LICENSE). Price Index data is CC BY 4.0, as above. Catalogue content is not what this chart runs, and it is not covered by either licence.

## Artifact Hub

The release workflow pushes this chart to `oci://registry-1.docker.io/coworkingview/cwv-helm` and pushes [`artifacthub-repo.yml`](artifacthub-repo.yml) to `registry-1.docker.io/coworkingview/cwv-helm:artifacthub.io`.

To list it on [Artifact Hub](https://artifacthub.io):

| Field | Value |
|---|---|
| Kind | Helm OCI |
| URL | `oci://registry-1.docker.io/coworkingview/cwv-helm` |

`repositoryID` in `artifacthub-repo.yml` is empty until that repository exists and its control-panel ID is known. The owner is CoworkingView, `info@coworkingview.com`.

The chart icon is the 192×192 CoworkingView mark at [`power-platform-connector/icon.png`](https://github.com/coworkingview/flex-office-data/blob/main/power-platform-connector/icon.png) (serif "CV", gold dot, off-white ground), served from the raw GitHub URL in `Chart.yaml`.
