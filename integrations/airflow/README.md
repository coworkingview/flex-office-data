# airflow-provider-coworkingview

Apache Airflow provider for the public [CoworkingView](https://coworkingview.com) Price Index.

`CoworkingViewHook` calls `GET /v1/market/rates` on `https://api.coworkingview.com` and turns the response into one row per product (flex desk, fixed desk, private office, day pass, meeting room, and any later aggregate the API adds). `CoworkingViewRatesOperator` does that for one city and returns the document through XCom. Set `output_path` to write the same JSON to a file.

The API is public. There is no API key. The Price Index is open data under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Every result carries the API's `attribution` string; keep it with anything you publish.

This package does not search the workspace catalogue. `GET /v1/properties` is a different endpoint, and the catalogue notice forbids bulk extraction.

**Homepage:** https://coworkingview.com

**Source:** https://github.com/coworkingview/flex-office-data

## Install

Python 3.10 or newer, and Apache Airflow 2.10 or newer (Airflow 3 is supported by the same imports).

Install Airflow first, with the constraint file for the Airflow and Python versions you run, then install this provider:

```bash
pip install "apache-airflow==2.10.5" \
  --constraint "https://raw.githubusercontent.com/apache/airflow/constraints-2.10.5/constraints-3.12.txt"
pip install "git+https://github.com/coworkingview/flex-office-data.git#subdirectory=integrations/airflow"
```

From a checkout of this repository:

```bash
pip install ./integrations/airflow
```

Confirm Airflow sees the provider:

```bash
airflow providers get airflow-provider-coworkingview
```

## Connection

A connection is optional. With none configured, the hook uses `https://api.coworkingview.com`.

To point at another root (a mirror, or a staging API), add a connection of type `coworkingview`. The host is the API root, with no path. Leave login and password empty.

```bash
airflow connections add coworkingview_default \
  --conn-type coworkingview \
  --conn-host https://api.coworkingview.com
```

`COWORKINGVIEW_API_URL` is the other override. The connection host wins when both are set.

The connection id operators use by default is `coworkingview_default`.

## Usage

```python
from coworkingview_provider.operators.rates import CoworkingViewRatesOperator

berlin = CoworkingViewRatesOperator(
    task_id="berlin_price_index",
    city="berlin",
    output_path="/tmp/coworkingview-{{ ds }}-berlin-rates.json",
)
```

`city` is the city slug (`berlin`, `madrid`, `abu-dhabi`). `locale` defaults to `en` (`es` and `de` are the other values the API accepts; a request without `locale` is rejected). `currency` is optional: `EUR`, `GBP`, `USD`, `CHF`, `AED`, or `VES`. Omit it to keep the city's own currency. `product` limits the rows to one product, for example `flex_desk`.

The return value is the XCom. A downstream task reads it with `ti.xcom_pull(task_ids="berlin_price_index")`. The file, when `output_path` is set, is that same object.

```json
{
  "city": "berlin",
  "city_name": "Berlin",
  "country_code": "DE",
  "currency": "USD",
  "locale": "en",
  "as_of": "2026-10-27T21:06:48.313Z",
  "attribution": "Source: CoworkingView Price Index (https://coworkingview.com/en/tools/price-index), ...",
  "license": "https://creativecommons.org/licenses/by/4.0/",
  "contract_version": "1.0.0",
  "rates": [
    {
      "city_slug": "berlin",
      "product": "flex_desk",
      "unit": "month",
      "currency": "USD",
      "median": 233,
      "p25": 216,
      "p75": 317,
      "sample_size": 72,
      "property_count": 66,
      "operator_count": 38,
      "low_confidence": false,
      "as_of": "2026-10-27T21:06:48.313Z",
      "attribution": "Source: CoworkingView Price Index (https://coworkingview.com/en/tools/price-index), ...",
      "license": "https://creativecommons.org/licenses/by/4.0/"
    }
  ]
}
```

Those amounts are the recorded response in `spec/fixtures/market_rates_berlin_usd.json` (`currency=USD`). A live call returns the current index; `as_of` says when it was computed. `low_confidence` is true when `sample_size` is below 10.

`median`, `p25` and `p75` are the API's `.amount` fields. `p25` and `p75` are `null` when the API does not publish them (the `byType` fallback, and some day-pass and meeting-room statistics).

An example DAG is `example_dags/example_coworkingview_rates.py`.

From a hook, outside an operator:

```python
from coworkingview_provider.hooks.coworkingview import CoworkingViewHook

rates = CoworkingViewHook().get_city_rates(city="berlin", currency="EUR")
```

HTTP 429 and 5xx are retried once. The wait is the `Retry-After` header, else `RateLimit-Reset`, else 2 seconds, and never more than 10 seconds. Any other error fails the task. The client sends `User-Agent: airflow-provider-coworkingview/0.1.0 (+https://github.com/coworkingview/flex-office-data)`.

## Develop

From `integrations/airflow`, with Airflow already installed:

```bash
pip install -e ".[dev]"
pytest
ruff check .
ruff format --check .
python -m build
```

Tests mock HTTP. They do not call `api.coworkingview.com`. The GitHub Actions workflow `.github/workflows/airflow-provider.yml` installs Airflow, runs the tests, and builds the sdist and wheel.

## Licence

The provider code is MIT. See [LICENSE](LICENSE).

The Price Index data is not covered by that licence. It is CC BY 4.0. The `attribution` and `license` fields in the operator result are the credit the API asks you to keep.
