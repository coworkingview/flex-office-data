"""SDK standard tests, plus the tap's own HTTP behaviour. All mocked."""

from __future__ import annotations

import json

import pytest
from singer_sdk.exceptions import FatalAPIError, RetriableAPIError
from singer_sdk.testing import SuiteConfig, get_tap_test_class

from tap_coworkingview.client import retry_wait_seconds
from tap_coworkingview.tap import TapCoworkingView
from tests.support import dump_json

SAMPLE_CONFIG = {"city": "berlin"}

TestTapCoworkingView = get_tap_test_class(
    tap_class=TapCoworkingView,
    config=SAMPLE_CONFIG,
    suite_config=SuiteConfig(max_records_limit=10),
)


def _tap(config: dict | None = None) -> TapCoworkingView:
    return TapCoworkingView(config=config if config is not None else SAMPLE_CONFIG)


def _stream(tap: TapCoworkingView, name: str):
    return tap.streams[name]


def _sync(stream) -> list[dict]:
    return list(stream.get_records(None))


def test_discover_has_both_streams() -> None:
    catalog = _tap().catalog_dict
    names = {stream["tap_stream_id"] for stream in catalog["streams"]}
    assert names == {"workspaces", "market_rates"}


def test_no_request_until_sync(api) -> None:
    before = len(api["mocker"].request_history)
    _tap()
    assert len(api["mocker"].request_history) == before


def test_default_city_and_endpoints(api) -> None:
    tap = _tap({})
    workspaces = _sync(_stream(tap, "workspaces"))
    rates = _sync(_stream(tap, "market_rates"))
    assert [row["slug"] for row in workspaces] == [
        "sankt-oberholz-rosenthaler-berlin",
        "smartspaces-berlin-spandau",
        "regus-charlottenburg-berlin",
    ]
    assert "images" not in workspaces[0]
    assert "excerpt" not in workspaces[0]
    assert workspaces[0]["attribution"].startswith("Source: CoworkingView")
    assert "not permitted" in workspaces[0]["notice"]
    berlin = [row for row in rates if row["city_slug"] == "berlin" and row["product"] == "flex_desk"]
    assert berlin[0]["median"] == 214
    assert berlin[0]["low_confidence"] is False
    assert "CC BY 4.0" in berlin[0]["attribution"]
    assert berlin[0]["license"] == "https://creativecommons.org/licenses/by/4.0/"

    calls = api["mocker"].request_history
    properties = [call for call in calls if call.path.endswith("/v1/properties")]
    rates_calls = [call for call in calls if call.path.endswith("/v1/market/rates")]
    assert properties[0].qs["city"] == ["berlin"]
    assert properties[0].qs["locale"] == ["en"]
    assert properties[0].qs["sortby"] == ["date-desc"]
    assert properties[0].qs["pagesize"] == ["50"]
    assert properties[0].qs["page"] == ["1"]
    assert "seed" not in properties[0].qs
    assert rates_calls[0].qs["city"] == ["berlin"]
    assert rates_calls[0].hostname == "api.coworkingview.com"
    assert properties[0].headers["Accept"] == "application/json"
    assert properties[0].headers["User-Agent"].startswith("tap-coworkingview/")
    assert "Authorization" not in properties[0].headers


def test_city_and_api_url_override(api) -> None:
    tap = _tap({"city": "madrid", "api_url": "https://example.test/root/"})
    _sync(_stream(tap, "market_rates"))
    call = api["mocker"].request_history[-1]
    assert call.hostname == "example.test"
    assert call.path == "/root/v1/market/rates"
    assert call.qs["city"] == ["madrid"]


def test_pagination_stops_at_200_listings(api) -> None:
    def properties(request, context):
        page = int(request.qs.get("page", ["1"])[0])
        records = []
        for index in range(50):
            number = (page - 1) * 50 + index
            records.append(
                {
                    "slug": f"space-{number}",
                    "title": f"Space {number}",
                    "countryCode": "DE",
                    "city": {"slug": "berlin", "name": "Berlin"},
                    "featured": False,
                    "updatedAt": "2026-10-19T16:27:57.522Z",
                }
            )
        return dump_json(
            context,
            {
                "data": records,
                "meta": {
                    "pagination": {
                        "page": page,
                        "pageSize": 50,
                        "total": 500,
                        "pageCount": 10,
                    },
                    "citation": {"text": "Source: test."},
                    "catalogueNotice": "Link, do not copy the catalogue.",
                },
            },
        )

    api["properties"] = properties
    rows = _sync(_stream(_tap(), "workspaces"))
    assert len(rows) == 200
    assert rows[0]["slug"] == "space-0"
    assert rows[-1]["slug"] == "space-199"
    pages = [
        call.qs["page"][0]
        for call in api["mocker"].request_history
        if call.path.endswith("/v1/properties")
    ]
    assert pages == ["1", "2", "3", "4"]


def test_retries_429_once(api) -> None:
    attempts = {"count": 0}

    def rates(request, context):
        del request
        attempts["count"] += 1
        if attempts["count"] == 1:
            return dump_json(
                context, {"code": "RATE_LIMIT"}, status=429, headers={"Retry-After": "0"}
            )
        return dump_json(context, {"data": {"cities": [], "asOf": None}})

    api["rates"] = rates
    rows = _sync(_stream(_tap(), "market_rates"))
    assert rows == []
    assert attempts["count"] == 2


def test_does_not_retry_a_400(api) -> None:
    attempts = {"count": 0}

    def rates(request, context):
        del request
        attempts["count"] += 1
        return dump_json(
            context,
            {"title": "Bad Request", "status": 400, "code": "VALIDATION", "detail": "no"},
            status=400,
        )

    api["rates"] = rates
    with pytest.raises(FatalAPIError):
        _sync(_stream(_tap(), "market_rates"))
    assert attempts["count"] == 1


def test_retries_500_once_then_raises(api) -> None:
    attempts = {"count": 0}

    def rates(request, context):
        del request
        attempts["count"] += 1
        return dump_json(context, {"code": "SERVER"}, status=503, headers={"Retry-After": "0"})

    api["rates"] = rates
    with pytest.raises(RetriableAPIError):
        _sync(_stream(_tap(), "market_rates"))
    assert attempts["count"] == 2


def test_blank_city_is_rejected() -> None:
    tap = _tap({"city": "  "})
    with pytest.raises(ValueError, match="city"):
        _sync(_stream(tap, "workspaces"))


def test_retry_wait_uses_retry_after_then_reset_then_fallback() -> None:
    assert retry_wait_seconds({"Retry-After": "3"}) == 3
    assert retry_wait_seconds({"RateLimit-Reset": "4"}) == 4
    assert retry_wait_seconds({}) == 2
    assert retry_wait_seconds({"Retry-After": "30"}) == 10


def test_about_lists_settings_and_capabilities() -> None:
    import subprocess
    import sys

    completed = subprocess.run(
        [sys.executable, "-m", "tap_coworkingview", "--about", "--format=json"],
        check=True,
        capture_output=True,
        text=True,
    )
    payload = json.loads(completed.stdout)
    names = set(payload["settings"]["properties"])
    assert "city" in names
    assert "api_url" in names
    assert "api_key" not in names
    assert "catalog" in payload["capabilities"]
    assert "discover" in payload["capabilities"]
