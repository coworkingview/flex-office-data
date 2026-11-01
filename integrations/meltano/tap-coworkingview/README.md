# tap-coworkingview

Singer tap for the public API of [CoworkingView](https://coworkingview.com).

It extracts, for one city:

- **workspaces** — coworking listings (`GET /v1/properties`), each with a link to its page on [coworkingview.com](https://coworkingview.com). At most 200 listings per sync, the same ceiling as the other clients in this repository.
- **market_rates** — the [CoworkingView Price Index](https://coworkingview.com/en/tools/price-index) (`GET /v1/market/rates`): median, p25 and p75 by product. Open data under **CC BY 4.0**. Every row carries `attribution` and `license`; keep them with anything you publish.

The API is public. There is no API key. Listings are ordered `date-desc` so a multi-page sync stays stable. Photos, descriptions and logos are left on the listing page.

Built with the [Meltano Singer SDK](https://sdk.meltano.com/).

## Install

```bash
pip install git+https://github.com/coworkingview/flex-office-data.git#subdirectory=integrations/meltano/tap-coworkingview
```

Requires Python 3.10 or newer.

## Configure

| setting | default | description |
|---|---|---|
| `city` | `berlin` | City slug, for example `berlin`, `madrid`, `abu-dhabi` |
| `api_url` | `https://api.coworkingview.com` | API root, if you need to point the tap elsewhere |

```bash
tap-coworkingview --config config.json --discover > catalog.json
tap-coworkingview --config config.json --catalog catalog.json
```

`config.json`:

```json
{"city": "berlin"}
```

## Meltano

An example project file is `meltano.yml` in this directory. In your own project:

```bash
meltano init coworkingview-elt
cd coworkingview-elt
meltano add extractor tap-coworkingview --pip-url "git+https://github.com/coworkingview/flex-office-data.git#subdirectory=integrations/meltano/tap-coworkingview"
meltano config set tap-coworkingview city berlin
meltano select tap-coworkingview --all
meltano run tap-coworkingview
```

## Develop

From this directory, with the repository checked out (the tests read `spec/fixtures/`):

```bash
pip install -e ".[dev]"
pytest
```

Tests mock HTTP. They do not call `api.coworkingview.com`.
