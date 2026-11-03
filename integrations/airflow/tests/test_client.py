"""HTTP behaviour of the Price Index client. No live calls."""

from __future__ import annotations

import json
import urllib.error
from unittest.mock import patch

import pytest

from coworkingview_provider.client import (
    USER_AGENT,
    CoworkingViewClient,
    normalize_base_url,
    retry_wait_seconds,
)
from coworkingview_provider.exceptions import CoworkingViewApiError, CoworkingViewError
from tests.support import Response, berlin_rates, http_error, json_response


def _capture(body_or_error):
    seen: dict = {}

    def _open(request, timeout=None):
        seen["url"] = request.full_url
        seen["headers"] = {key.lower(): value for key, value in request.headers.items()}
        seen["method"] = request.get_method()
        seen["timeout"] = timeout
        seen["calls"] = seen.get("calls", 0) + 1
        if isinstance(body_or_error, Exception):
            raise body_or_error
        if isinstance(body_or_error, list):
            item = body_or_error.pop(0)
            if isinstance(item, Exception):
                raise item
            return item
        return body_or_error

    return seen, _open


def test_city_rates_calls_the_public_rates_endpoint():
    seen, _open = _capture(json_response(berlin_rates()))
    client = CoworkingViewClient()
    with patch("urllib.request.urlopen", side_effect=_open):
        document = client.city_rates(city="berlin", currency="usd")

    assert seen["method"] == "GET"
    assert seen["url"].startswith("https://api.coworkingview.com/v1/market/rates?")
    assert "locale=en" in seen["url"]
    assert "city=berlin" in seen["url"]
    assert "currency=USD" in seen["url"]
    assert "/v1/properties" not in seen["url"]
    assert seen["headers"]["accept"] == "application/json"
    assert seen["headers"]["user-agent"] == USER_AGENT
    assert "airflow-provider-coworkingview/0.1.0" in USER_AGENT
    assert "authorization" not in seen["headers"]
    assert seen["timeout"] == 20.0
    assert document["rates"][0]["product"] == "flex_desk"
    assert document["rates"][0]["median"] == 233


def test_invalid_arguments_do_not_send_a_request():
    client = CoworkingViewClient()
    with patch("urllib.request.urlopen") as urlopen:
        with pytest.raises(ValueError, match="locale"):
            client.city_rates(city="berlin", locale="fr")
        with pytest.raises(ValueError, match="currency"):
            client.city_rates(city="berlin", currency="XYZ")
        with pytest.raises(ValueError, match="product"):
            client.city_rates(city="berlin", product="hot_desk")
        with pytest.raises(ValueError, match="city"):
            client.city_rates(city="  ")
    urlopen.assert_not_called()


def test_retries_once_on_429_then_returns_the_body():
    slept: list[float] = []
    error = http_error(429, b"", {"Retry-After": "0"})
    seen, _open = _capture([error, json_response(berlin_rates())])
    client = CoworkingViewClient()
    client._sleep = slept.append
    with patch("urllib.request.urlopen", side_effect=_open):
        document = client.city_rates(city="berlin")
    assert seen["calls"] == 2
    assert slept == [0.0]
    assert document["city"] == "berlin"


def test_second_server_error_is_raised():
    slept: list[float] = []
    errors = [
        http_error(503, '{"title": "down", "code": "UNAVAILABLE"}', {"Retry-After": "999"}),
        http_error(503, '{"title": "down", "code": "UNAVAILABLE"}'),
    ]
    client = CoworkingViewClient()
    client._sleep = slept.append
    with (
        patch("urllib.request.urlopen", side_effect=errors),
        pytest.raises(CoworkingViewApiError, match="UNAVAILABLE") as caught,
    ):
        client.city_rates(city="berlin")
    assert caught.value.status == 503
    assert slept == [10.0]


def test_validation_problem_is_not_retried():
    body = json.dumps(
        {
            "title": "Validation failed",
            "status": 400,
            "code": "VALIDATION_FAILED",
            "detail": 'currency "VES" has no approximate rate from "EUR".',
        }
    )
    client = CoworkingViewClient()
    client._sleep = lambda _seconds: pytest.fail("400 must not be retried")
    with (
        patch("urllib.request.urlopen", side_effect=http_error(400, body)),
        pytest.raises(CoworkingViewApiError, match="VALIDATION_FAILED") as caught,
    ):
        client.city_rates(city="berlin", currency="VES")
    assert caught.value.status == 400
    assert "VES" in (caught.value.detail or "")


def test_invalid_json_and_non_object_json():
    client = CoworkingViewClient()
    with (
        patch("urllib.request.urlopen", return_value=Response(b"not-json")),
        pytest.raises(CoworkingViewApiError, match="not valid JSON"),
    ):
        client.city_rates(city="berlin")
    with (
        patch("urllib.request.urlopen", return_value=Response(b"[1]")),
        pytest.raises(CoworkingViewApiError, match="not an object"),
    ):
        client.city_rates(city="berlin")


def test_connection_failure():
    client = CoworkingViewClient()
    with (
        patch(
            "urllib.request.urlopen",
            side_effect=urllib.error.URLError("name resolution failed"),
        ),
        pytest.raises(CoworkingViewError, match="Could not reach"),
    ):
        client.city_rates(city="berlin")


def test_base_url_must_be_the_api_root():
    with pytest.raises(CoworkingViewError, match="http"):
        normalize_base_url("file:///etc/passwd")
    with pytest.raises(CoworkingViewError, match="username"):
        normalize_base_url("https://user:secret@api.coworkingview.com")
    with pytest.raises(CoworkingViewError, match="path"):
        normalize_base_url("https://api.coworkingview.com/v1")
    assert normalize_base_url("api.coworkingview.com/") == "https://api.coworkingview.com"


def test_retry_wait_uses_rate_limit_reset_then_the_fallback():
    assert retry_wait_seconds({"RateLimit-Reset": "3"}) == 3.0
    assert retry_wait_seconds({}) == 2.0
    assert retry_wait_seconds({"Retry-After": "1", "RateLimit-Reset": "9"}) == 1.0


def test_country_is_sent_and_none_parameters_are_dropped():
    seen, _open = _capture(json_response(berlin_rates()))
    client = CoworkingViewClient(base_url="https://mirror.test")
    with patch("urllib.request.urlopen", side_effect=_open):
        client.city_rates(city="berlin", country="DE", currency=None)
    assert seen["url"].startswith("https://mirror.test/v1/market/rates?")
    assert "country=DE" in seen["url"]
    assert "currency" not in seen["url"]
