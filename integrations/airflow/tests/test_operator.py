"""CoworkingViewRatesOperator pushes XCom and can write the same JSON file."""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path
from unittest.mock import patch

import pytest
from airflow.exceptions import AirflowNotFoundException

from coworkingview_provider.operators.rates import CoworkingViewRatesOperator, write_rates_file
from tests.support import berlin_rates, json_response

_MISSING = AirflowNotFoundException("missing")


def _open_factory():
    def _open(request, timeout=None):
        return json_response(berlin_rates())

    return _open


def test_execute_returns_the_xcom_document():
    operator = CoworkingViewRatesOperator(
        task_id="berlin_price_index",
        city="berlin",
        currency="USD",
    )
    with (
        patch(
            "coworkingview_provider.hooks.coworkingview.CoworkingViewHook.get_connection",
            side_effect=_MISSING,
        ),
        patch("urllib.request.urlopen", side_effect=_open_factory()),
    ):
        payload = operator.execute({})
    assert payload["city"] == "berlin"
    assert payload["currency"] == "USD"
    assert payload["rates"][0]["median"] == 233
    assert payload["attribution"].startswith("Source: CoworkingView")
    assert "CoWoS" not in json.dumps(payload)


def test_execute_writes_the_same_document(tmp_path: Path):
    target = tmp_path / "nested" / "berlin.json"
    operator = CoworkingViewRatesOperator(
        task_id="berlin_price_index",
        city=" berlin ",
        currency="USD",
        product="flex_desk",
        output_path=str(target),
    )
    with (
        patch(
            "coworkingview_provider.hooks.coworkingview.CoworkingViewHook.get_connection",
            side_effect=_MISSING,
        ),
        patch("urllib.request.urlopen", side_effect=_open_factory()),
    ):
        payload = operator.execute({})
    written = json.loads(target.read_text(encoding="utf-8"))
    assert written == payload
    assert [row["product"] for row in written["rates"]] == ["flex_desk"]
    assert not list(tmp_path.rglob("*.tmp"))


def test_bad_locale_fails_before_http():
    operator = CoworkingViewRatesOperator(task_id="rates", city="berlin", locale="fr")
    with patch("urllib.request.urlopen") as urlopen, pytest.raises(ValueError, match="locale"):
        operator.execute({})
    urlopen.assert_not_called()


def test_output_path_rejects_urls(tmp_path: Path):
    with pytest.raises(ValueError, match="local filesystem"):
        write_rates_file("https://example.test/rates.json", {"rates": []})
    directory = tmp_path / "dir"
    directory.mkdir()
    with pytest.raises(ValueError, match="directory"):
        write_rates_file(str(directory), {"rates": []})


def test_example_dag_defines_the_berlin_task():
    path = Path(__file__).resolve().parents[1] / "example_dags" / "example_coworkingview_rates.py"
    spec = importlib.util.spec_from_file_location("example_coworkingview_rates", path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert module.dag.dag_id == "example_coworkingview_rates"
    task = module.dag.get_task("berlin_price_index")
    assert isinstance(task, CoworkingViewRatesOperator)
    assert task.city == "berlin"
    assert task.output_path == "/tmp/coworkingview-{{ ds }}-berlin-rates.json"
