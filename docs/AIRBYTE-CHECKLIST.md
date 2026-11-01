# Airbyte source-coworkingview checklist

Manifest-only community source for the public CoworkingView API, laid out so it can be copied into [airbytehq/airbyte](https://github.com/airbytehq/airbyte). This file records the live validation, the upstream rules, and the pull request to open there. Nothing in this repository was submitted to airbytehq.

Validated on 2026-11-01 with `airbyte-cdk` 7.39.1, the same CDK as `docker.io/airbyte/source-declarative-manifest:7.39.1`.

## Where the files are

| Path in this repo | Path it maps to in airbytehq/airbyte |
| --- | --- |
| `integrations/airbyte/upstream-layout/airbyte-integrations/connectors/source-coworkingview/` | `airbyte-integrations/connectors/source-coworkingview/` |
| `integrations/airbyte/upstream-layout/docs/integrations/sources/coworkingview.md` | `docs/integrations/sources/coworkingview.md` |

`integrations/airbyte/source-coworkingview/` is the same connector directory. CI fails if the two copies differ.

## What the connector does

- Public API, no key. Base URL `https://api.coworkingview.com`. `allowedHosts` is `api.coworkingview.com`.
- `properties`: `GET /v1/properties?locale=<locale>&city=<city>&sortBy=date-desc`, paged with `page` and `pageSize`.
- `market_rates`: `GET /v1/market/rates?locale=<locale>&city=<city>`. One response. No paginator.
- Spec inputs: `city` (default `berlin`) and `locale` (default `en`, enum `en` / `de` / `es`). The API rejects a request that omits a valid locale (`400 VALIDATION_FAILED`). The manifest sends `en` and `berlin` when the config leaves them blank, so an empty config still checks.
- Connection check reads `market_rates` (one request). An unknown city returns HTTP 200 with an empty `cities` array, so the check fails closed. A bad locale returns HTTP 400 and is a config error.
- Full refresh only. No incremental cursor exists on either endpoint.

### Pagination, from the live API

`GET /v1/properties?locale=en&city=berlin&page=1&pageSize=50&sortBy=date-desc` on 2026-11-01 returned:

```text
meta.pagination = {"page": 1, "pageSize": 50, "total": 143, "pageCount": 3}
```

Pages 1–3 returned 50, 50 and 43 rows. The three pages had 143 distinct `slug`s and no overlap. `pageSize=51` is rejected (`400`, "Too big: expected number to be <=50"), so the paginator requests 50 and stops when a page is shorter than 50 (`PageIncrement`).

`sortBy=date-desc` is set because the API default is `random`. A random page order repeats and skips rows across pages. With `date-desc` the response has no `meta.seed`. The seed only showed up on unsorted (random) responses.

`GET /v1/market/rates?locale=en&city=berlin` returns one object. `meta` is `{contractVersion}` and has no `pagination`. The stream does not paginate.

### Schemas

Schemas list fields observed on the live API on 2026-11-01. Nothing was added that the responses did not contain.

`properties` is each element of `data`, plus two values copied from the same response so they are not dropped: `meta.citation` and `meta.catalogueNotice`. Photos (`images`), listing text (`excerpt`) and `operator.logo` are removed before emit. The catalogue notice returned with the search says descriptions, images and logos are not licensed for reuse. The same exclusion is what the other clients in this repository do.

`market_rates` is each element of `data.cities`, plus the dataset fields that sit next to `cities` on that response: `attribution`, `license`, `licenseUrl`, `asOf`, `scope`, `copyright`. The Price Index is `CC-BY-4.0`. `city_slug` is `city.slug` copied to the top level. CDK 7.39.1 raises `Nested primary keys are not supported` for `[['city', 'slug']]`.

A read of Berlin produced 143 `properties` records and 1 `market_rates` record. Every record validated against its inline schema (`additionalProperties: true`). No record contained `images`, `excerpt` or `operator.logo`. The rate row was `city_slug=berlin`, `license=CC-BY-4.0`, with the API's attribution string.

Field sets (union of emitted records):

- `properties`: `slug`, `title`, `countryCode`, `city`, `zone`, `operator`, `coordinates`, `fromPrice`, `fromBillingPeriod`, `featured`, `updatedAt`, `amenities`, `capacity`, `marketPosition`, `citation`, `catalogueNotice`.
- `market_rates`: `city_slug`, `city`, `countryCode`, `currency`, `byType`, `figures`, `dayPass`, `meetingRoom`, `buildings`, `propertyCount`, `operatorCount`, `insufficientData`, `p25`, `p75`, `min`, `max`, `entryMedian`, `entryMin`, `entryMax`, `sampleSize`, `attribution`, `license`, `licenseUrl`, `asOf`, `scope`, `copyright`.

`dayPass` and `meetingRoom` are absent on many cities in an unfiltered index (present on 7 and 4 of 72 cities that day). They are in the schema and not required. City-level `p25` / `p75` are null on some cities, so those money objects allow null. Amounts are `number` because some medians are floats (5 of 128 listing prices, and one day-pass median).

## Validation results

Commands were run from the repo root with `airbyte-cdk==7.39.1` (`source-declarative-manifest` on `PATH`).

### spec

`source-declarative-manifest spec` with no manifest mounted at `/airbyte/integration_code/source_declarative_manifest/manifest.yaml` returns the generic declarative spec (`__injected_declarative_manifest`). That is the CLI's remote-manifest path. This environment cannot create that mount path.

The connector spec is what the image runs once the manifest is bundled. Same class the CLI uses for that path, `YamlDeclarativeSource.spec()`:

| Input | Default |
| --- | --- |
| `city` | `berlin` |
| `locale` | `en` |

### check

| Config | Result |
| --- | --- |
| `{"city":"berlin","locale":"en"}` | `SUCCEEDED` |
| `{}` (manifest fills `berlin` / `en`) | `SUCCEEDED` |
| `{"city":"berlin","locale":"fr"}` | `FAILED`. HTTP 400 `VALIDATION_FAILED`: locale must be `en`, `de` or `es`. Message: "CoworkingView rejected the request. Use a city slug such as berlin and a locale of en, de or es." |

CLI, same success:

```bash
source-declarative-manifest check \
  --config integrations/airbyte/source-coworkingview/integration_tests/config.json \
  --manifest-path integrations/airbyte/source-coworkingview/manifest.yaml
```

`{"status": "SUCCEEDED"}`.

### discover

```bash
source-declarative-manifest discover \
  --config integrations/airbyte/source-coworkingview/integration_tests/config.json \
  --manifest-path integrations/airbyte/source-coworkingview/manifest.yaml
```

| Stream | Primary key | Sync modes |
| --- | --- | --- |
| `properties` | `slug` | `full_refresh` |
| `market_rates` | `city_slug` | `full_refresh` |

### read

`YamlDeclarativeSource.read` of both streams against Berlin:

| Stream | Records | Schema errors |
| --- | --- | --- |
| `properties` | 143 | 0 |
| `market_rates` | 1 | 0 |

CLI read of `market_rates` only:

```bash
source-declarative-manifest read \
  --config integrations/airbyte/source-coworkingview/integration_tests/config.json \
  --catalog /tmp/rates-catalog.json \
  --manifest-path integrations/airbyte/source-coworkingview/manifest.yaml
```

1 record, `city_slug` `berlin`, `license` `CC-BY-4.0`.

`integrations/airbyte/scripts/validate_manifest.py` repeats spec, check, discover and read and exits non-zero on a failed check, a short `properties` read (pagination did not run), a `market_rates` count other than 1, a schema error, or catalog drift. CI runs it.

## Models

Three manifest-only "new source" pull requests merged in September–October 2026. File lists taken from the GitHub API.

| PR | Merged | Files |
| --- | --- | --- |
| [88377](https://github.com/airbytehq/airbyte/pull/88377) `feat(source-gemini): new Gemini for Google Workspace source connector` | 2026-10-26 | `manifest.yaml`, `metadata.yaml`, `icon.svg`, `README.md`, `acceptance-test-config.yml`, `docs/integrations/sources/gemini.md` |
| [88374](https://github.com/airbytehq/airbyte/pull/88374) `feat(source-openai): contribution from Ella6882` | 2026-10-26 | same five connector files plus `docs/integrations/sources/openai.md` |
| [86351](https://github.com/airbytehq/airbyte/pull/86351) `feat(source-openai-ads): 🎉 New Source: OpenAI Ads` | 2026-10-08 | those files plus `integration_tests/invalid_config.json` |

Ours follows that layout and, like 86351, commits a config the acceptance tests can run. The API is public, so the valid config is in git. Invalid config is `locale: fr`.

Docs voice follows the current [PokéAPI source page](https://github.com/airbytehq/airbyte/blob/master/docs/integrations/sources/pokeapi.md): the title sentence links the product site, then Overview, Prerequisites, Setup guide, Supported sync modes, Supported streams, Limitations, Rate limits, Changelog. The product link is `https://coworkingview.com` with no `www`. The API's own attribution string still contains `www`; the connector does not rewrite it.

`metadata.yaml` on master for `source-gemini`, `source-openai` and `source-pokeapi` (read 2026-11-01) pins:

```text
docker.io/airbyte/source-declarative-manifest:7.39.1@sha256:dc2fc3c346aee695a7967db5c1a0701732a2d075f0c67856934eb1f4b360f06d
```

Tags are `language:manifest-only` and `cdk:low-code`. `remoteRegistries.pypi.enabled` is `false`. `license` is `ELv2`. `supportLevel` is `community`. `releaseStage` is `alpha`. `dockerImageTag` for a first release is `0.0.1`. `ab_internal.ql` and `sl` are 100. No Dockerfile.

## Upstream rules

| Rule | Source | How this connector meets it |
| --- | --- | --- |
| User-facing docs at `docs/integrations/sources/<name>.md`, with a changelog row for the version | [QA checks](https://docs.airbyte.com/community/contributing-to-airbyte/resources/qa-checks) | `docs/integrations/sources/coworkingview.md`, version `0.0.1` dated 2026-11-01. The PR number cell is empty until the airbytehq pull request exists. |
| Docs intro links the product the way PokéAPI links pokeapi.co | [pokeapi.md](https://github.com/airbytehq/airbyte/blob/master/docs/integrations/sources/pokeapi.md) | "setup guide and reference information for the [CoworkingView](https://coworkingview.com) source connector." |
| Supported sync modes sentence | QA checks, "Supported sync modes" | The section uses that sentence and links `https://docs.airbyte.com/cloud/core-concepts/#connection-sync-modes`. |
| Valid `metadata.yaml` | [Connector metadata](https://docs.airbyte.com/platform/connector-development/connector-metadata-file) | `metadataSpecVersion: "1.0"`, definition id `12e8aad2-ec05-4f13-a792-bbdd60b5a526`, `connectorType: source`, `connectorSubtype: api`, `dockerRepository: airbyte/source-coworkingview`, `documentationUrl: https://docs.airbyte.com/integrations/sources/coworkingview`, `githubIssueLabel: source-coworkingview`, registry overrides enabled for OSS and Cloud. |
| Language tag and CDK tag | QA checks | `language:manifest-only`, `cdk:low-code`. |
| Manifest-only base image is `airbyte/source-declarative-manifest` | QA checks | `connectorBuildOptions.baseImage` is the 7.39.1 image with the sha256 above. No Dockerfile. |
| Manifest `version` is the CDK used to build and test | declarative component schema (`DeclarativeSource.version`) | `version: "7.39.1"`. |
| Semantic version `0.0.1` for a new connector | [Pull request handbook](https://docs.airbyte.com/community/contributing-to-airbyte/resources/pull-requests-handbook), QA checks | `dockerImageTag: 0.0.1`. No breaking-change block. |
| License MIT or ELv2 | QA checks | `license: ELv2`. PyPI publishing is off, matching the manifest-only models, so there is no `pyproject.toml` to keep in sync. The Price Index *data* is CC BY 4.0; that is the dataset licence, not the connector licence. |
| Icon `icon.svg`, square, in the connector root | QA checks | `icon.svg`, `width="250"` `height="250"` `viewBox="0 0 250 250"`. Off-white ground, serif CV, gold dot, in the same spirit as `https://coworkingview.com/icon-192.png`. |
| HTTPS only | QA checks | Both URLs are `https://api.coworkingview.com/...`. |
| `acceptance-test-config.yml` uses `acceptance_tests` | [Acceptance tests reference](https://docs.airbyte.com/platform/connector-development/testing-connectors/connector-acceptance-tests-reference) | `connector_image: airbyte/source-coworkingview:dev`. `spec` points at `manifest.yaml`. `connection` expects success for `integration_tests/config.json` and failure for `integration_tests/invalid_config.json`. `discovery`, `basic_read` and `full_refresh` use the committed config and `integration_tests/configured_catalog.json`. `incremental` is bypassed because neither stream is incremental. No GSM secret: the API has no key. |
| README, docs and icon, or CI fails | [Contribute a new connector](https://docs.airbyte.com/platform/connector-development/submit-new-connector) | All three are in the upstream layout. README matches the manifest-only README used by source-gemini and source-openai (Usage, Local Development, `airbyte-ci` build and test). |
| Auth, pagination and incremental where they apply | Same page | No auth. Properties paginates. Rates does not. Incremental is not offered by the API and is documented as unsupported. |
| PR title is a conventional commit | [Pull request handbook](https://docs.airbyte.com/community/contributing-to-airbyte/resources/pull-requests-handbook) | Draft title below. `feat` is the type used for a new source. |
| Sandbox account | Contribute a new connector | Not required. Say so in the PR. Reviewers can call the public API. |

## Forks, maintainer edits, and linked issues

This is what airbytehq requires of the pull request that adds the connector. It is separate from the pull request in *this* repository.

From [Contributing to Airbyte](https://docs.airbyte.com/community/contributing-to-airbyte), section "Pull Request permission requirements", and the same text in the [airbyte README](https://github.com/airbytehq/airbyte/blob/master/README.md) (both read 2026-11-01):

1. Open the pull request from a fork on a **personal GitHub account**. A fork owned by an **organization** does not show "Allow edits from maintainers". GitHub withholds that checkbox on organization forks. Airbyte's wording: "You must also create your PR from a fork in your personal GitHub account rather than an organization account, or else you will not see this option."
2. Check **Allow edits from maintainers** (GitHub's checkbox; Airbyte also calls it "Allow edits by maintainers" in older templates). Maintainers use it to push formatting, security and dependency fixes onto the branch. Docs: [Allowing changes to a pull request branch created from a fork](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/working-with-forks/allowing-changes-to-a-pull-request-branch-created-from-a-fork).
3. Do **not** open the pull request from the fork's default branch. Airbyte says that blocks maintainers from pushing to the branch. Branch name format: `{YOUR_USERNAME}/{FEATURE/BUG}`, for example `jdoe/source-coworkingview`.
4. **Link an issue** that does not carry `needs triage`. "Pull requests without an issue attached take longer to review." If there is no issue, the description has to say what the problem is, how the pull request solves it, and which design decisions were made. [Contributing to Airbyte](https://docs.airbyte.com/community/contributing-to-airbyte), "Standard contribution workflow", steps 7 and the paragraph under "Code Contributions".

Connector-specific path, from [Contribute a New Connector](https://docs.airbyte.com/platform/connector-development/submit-new-connector):

- A low-code connector can be submitted from Connector Builder: **Publish → Contribute to Marketplace**, with a classic personal access token that has the `repo` scope and the `workflow` scope. Builder opens the pull request. The fork rules above still apply to that pull request.
- A Python or Java CDK connector is supposed to start from a **Discussion**, not only an issue: search [New Connector Request](https://github.com/airbytehq/airbyte/discussions/categories/new-connector-request) and, if nothing exists, [open one](https://github.com/airbytehq/airbyte/discussions/new?category=new-connector-request).
- A search of `airbytehq/airbyte` for `coworkingview` on 2026-11-01 returned no issue, pull request or discussion.

For a hand-opened manifest pull request, do both: open the New Connector Request discussion (the low-code page points custom connectors there, and a linked discussion gives reviewers the use case), and write the problem, the solution and the design in the pull request body so it is reviewable even before the discussion is triaged. Put the discussion URL in the body. Do not invent an issue number.

## Draft pull request for airbytehq/airbyte

Do not open this against airbytehq from the CoworkingView organization fork. Open it from a personal fork, on a non-default branch, with maintainer edits allowed, and link the discussion once it exists.

**Title**

```text
feat(source-coworkingview): 🎉 New Source: CoworkingView
```

**Body**

```markdown
## What

New manifest-only source for the public CoworkingView API (https://api.coworkingview.com). CoworkingView (https://coworkingview.com) publishes a catalogue of flexible workspaces and the CoworkingView Price Index. There is no Airbyte source for it. A search of issues, pull requests and discussions found nothing.

The author is affiliated with CoworkingView (info@coworkingview.com) and maintains the API this connector reads. This pull request was built with AI assistance. CoworkingView is responsible for the manifest, the field mapping and the validation below.

## How

Single manifest. No custom components. No API key.

- `properties`: `GET /v1/properties` for the configured city. Full refresh. `PageIncrement` on `page` / `pageSize` (the API rejects `pageSize` above 50). `sortBy=date-desc` so pages do not reshuffle. Primary key `slug`. Photos, logos and listing descriptions are removed. Each record keeps `citation` and `catalogueNotice` from that response.
- `market_rates`: `GET /v1/market/rates` for the same city. Full refresh. The endpoint does not paginate. One row per city in `data.cities`. Primary key `city_slug` (`city.slug` promoted, because CDK 7.39.1 rejects a nested primary key). The Price Index is CC BY 4.0. Each record keeps `attribution`, `license`, `licenseUrl`, `asOf`, `scope` and `copyright`.
- Spec: `city` (default `berlin`), `locale` (default `en`, one of `en` / `de` / `es`). The API requires the locale.
- Check reads `market_rates`. HTTP 400 and 404 are config errors. HTTP 429 and 5xx retry, honouring `Retry-After`.
- Base image `airbyte/source-declarative-manifest:7.39.1`.

No sandbox account is required. The API is public.

## Validation

`airbyte-cdk` 7.39.1 against the live API on 2026-11-01:

- spec: `city` default `berlin`, `locale` default `en`
- check: Berlin succeeded; empty config succeeded; `locale=fr` failed with the config-error message (HTTP 400)
- discover: `properties` and `market_rates`, full refresh only
- read: 143 listing records (3 pages, 143 distinct slugs) and 1 Price Index record, all matching the inline schemas

## User impact

New community source. No existing connector changes.
```
