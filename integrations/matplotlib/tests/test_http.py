"""The client calls ``GET /v1/market/rates`` and nowhere else."""

from __future__ import annotations

import json
import urllib.error

import pytest

from mpl_coworkingview import APIError, CoworkingViewError
from mpl_coworkingview._http import USER_AGENT, Client
from mpl_coworkingview._version import __version__

from .conftest import load_fixture
from .support import FakeOpener, http_error, json_response


def test_get_market_rates_url_and_user_agent() -> None:
    opener = FakeOpener([json_response(load_fixture("market_rates_berlin_usd.json"))])
    slept: list[float] = []
    client = Client(opener=opener, sleep=slept.append)
    result = client.market_rates(city="berlin", currency="usd", locale="en")
    flex = next(row for row in result.rows if row["product"] == "flex_desk")
    assert flex["median"] == 233
    assert flex["currency"] == "USD"
    assert slept == []
    request, timeout = opener.requests[0]
    assert timeout == 20
    assert request.full_url == (
        "https://api.coworkingview.com/v1/market/rates?locale=en&city=berlin&currency=USD"
    )
    assert request.get_header("Accept") == "application/json"
    assert request.get_header("User-agent") == USER_AGENT
    assert USER_AGENT.startswith(f"mpl-coworkingview/{__version__} ")
    assert request.get_method() == "GET"


def test_constructor_does_not_fetch() -> None:
    opener = FakeOpener([])
    Client(opener=opener)
    assert opener.requests == []


def test_validation_problem_is_not_retried() -> None:
    body = json.dumps(load_fixture("error_validation.json"))
    opener = FakeOpener([http_error(400, body)])
    client = Client(opener=opener, sleep=lambda _seconds: pytest.fail("slept"))
    with pytest.raises(APIError) as caught:
        client.market_rates(city="berlin", currency="VES")
    err = caught.value
    assert err.status == 400
    assert err.code == "VALIDATION_FAILED"
    assert err.errors[0]["path"] == "currency"
    assert len(opener.requests) == 1


def test_retry_once_on_500_then_success() -> None:
    slept: list[float] = []
    opener = FakeOpener(
        [
            http_error(500, b"", headers={"Retry-After": "1"}),
            json_response(load_fixture("market_rates.json")),
        ]
    )
    client = Client(opener=opener, sleep=slept.append)
    result = client.market_rates(locale="en")
    assert result.rows
    assert slept == [1.0]
    assert len(opener.requests) == 2
    assert all("/v1/market/rates?" in request.full_url for request, _timeout in opener.requests)


def test_second_500_is_raised() -> None:
    opener = FakeOpener([http_error(502, b""), http_error(502, b"")])
    client = Client(opener=opener, sleep=lambda _seconds: None)
    with pytest.raises(APIError) as caught:
        client.market_rates(locale="en")
    assert caught.value.status == 502
    assert caught.value.code == "HTTP_502"
    assert len(opener.requests) == 2


def test_non_json_body() -> None:
    opener = FakeOpener([ResponseBytes()])
    client = Client(opener=opener)
    with pytest.raises(APIError) as caught:
        client.market_rates(locale="en")
    assert caught.value.code == "BAD_RESPONSE"


class ResponseBytes:
    def __init__(self) -> None:
        self.status = 200
        self.reason = "OK"
        self.headers: dict[str, str] = {}

    def read(self) -> bytes:
        return b"not-json"

    def __enter__(self) -> ResponseBytes:
        return self

    def __exit__(self, *args: object) -> bool:
        return False


def test_connection_error() -> None:
    opener = FakeOpener([urllib.error.URLError("name lookup failed")])
    client = Client(opener=opener)
    with pytest.raises(CoworkingViewError, match="Could not reach"):
        client.market_rates(locale="en")


def test_bad_locale_does_not_fetch() -> None:
    opener = FakeOpener([])
    client = Client(opener=opener)
    with pytest.raises(ValueError, match="locale"):
        client.market_rates(locale="fr")
    assert opener.requests == []


def test_bad_currency_and_city() -> None:
    opener = FakeOpener([])
    client = Client(opener=opener)
    with pytest.raises(ValueError, match="currency"):
        client.market_rates(currency="btc")
    with pytest.raises(ValueError, match="city"):
        client.market_rates(city="../berlin")
    assert opener.requests == []
