"""Daily snapshot of the CoworkingView Price Index for Berlin.

The task return value is pushed to XCom. A downstream task reads it with
``ti.xcom_pull(task_ids="berlin_price_index")``. ``output_path`` writes the
same JSON document, including the CC BY 4.0 attribution, to a local file.

No connection is required. Add one of type ``coworkingview`` only to point
the hook at a different API root.
"""

from __future__ import annotations

from datetime import datetime, timezone

from airflow import DAG

from coworkingview_provider.operators.rates import CoworkingViewRatesOperator

with DAG(
    dag_id="example_coworkingview_rates",
    description="Fetch the CoworkingView Price Index for Berlin.",
    start_date=datetime(2026, 1, 1, tzinfo=timezone.utc),
    schedule="@daily",
    catchup=False,
    tags=["coworkingview"],
) as dag:
    CoworkingViewRatesOperator(
        task_id="berlin_price_index",
        city="berlin",
        output_path="/tmp/coworkingview-{{ ds }}-berlin-rates.json",
    )
