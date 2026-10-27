"""HTTP behaviour (SPEC section 2) against a local fake server."""

from __future__ import annotations

import socket
from datetime import datetime, timedelta, timezone
from email.utils import format_datetime

import pytest

import coworkingview
from coworkingview import APIError, Client, CoworkingViewError
from coworkingview._http import MAX_WAIT, retry_wait

from .conftest import FakeAPI, Reply

RATES_OK = {"data": {"cities": [], "asOf": "2026-10-27T21:06:48.313Z"}, "meta": {}}


def test_user_agent_and_accept(api: FakeAPI) -> None:
    api.queue(Reply(body=RATES_OK))
    api.client().rates()
    headers = api.requests[0].headers
    assert headers["user-agent"] == (
        f"coworkingview-python/{coworkingview.__version__} "
        "(+https://github.com/coworkingview/flex-office-data)"
    )
    assert headers["accept"] == "application/json"


def test_custom_user_agent(api: FakeAPI) -> None:
    api.queue(Reply(body=RATES_OK))
    api.client(user_agent="my-app/1.0").rates()
    assert api.requests[0].headers["user-agent"] == "my-app/1.0"


@pytest.mark.parametrize("status", [429, 500, 502, 503])
def test_retries_once_then_succeeds(api: FakeAPI, status: int) -> None:
    api.queue(Reply(status, {"title": "busy"}), Reply(body=RATES_OK))
    df = api.client().rates()
    assert df.empty
    assert len(api.requests) == 2
    assert api.sleeps == [2.0]  # no header: fixed 2 s


def test_retries_only_once(api: FakeAPI) -> None:
    api.queue(
        Reply(503, {"title": "Down", "code": "UNAVAILABLE"}),
        Reply(503, {"title": "Still down", "code": "UNAVAILABLE"}),
        Reply(body=RATES_OK),
    )
    with pytest.raises(APIError) as info:
        api.client().rates()
    assert len(api.requests) == 2
    assert info.value.status == 503
    assert info.value.title == "Still down"
    assert len(api.sleeps) == 1


def test_retry_after_is_honoured(api: FakeAPI) -> None:
    api.queue(Reply(429, {}, {"Retry-After": "3"}), Reply(body=RATES_OK))
    api.client().rates()
    assert api.sleeps == [3.0]


def test_retry_after_is_capped(api: FakeAPI) -> None:
    api.queue(Reply(429, {}, {"Retry-After": "120", "RateLimit-Reset": "5"}), Reply(body=RATES_OK))
    api.client().rates()
    assert api.sleeps == [MAX_WAIT]


def test_ratelimit_reset_used_without_retry_after(api: FakeAPI) -> None:
    api.queue(Reply(429, {}, {"RateLimit-Reset": "4"}), Reply(body=RATES_OK))
    api.client().rates()
    assert api.sleeps == [4.0]


def test_retry_wait_header_parsing() -> None:
    soon = datetime.now(timezone.utc) + timedelta(seconds=6)
    assert 4.0 <= retry_wait({"Retry-After": format_datetime(soon, usegmt=True)}) <= 6.0
    past = datetime.now(timezone.utc) - timedelta(minutes=5)
    assert retry_wait({"Retry-After": format_datetime(past, usegmt=True)}) == 0.0
    assert retry_wait({"Retry-After": "soon", "RateLimit-Reset": "1.5"}) == 1.5
    assert retry_wait({"Retry-After": "-3"}) == 0.0
    assert retry_wait({}) == 2.0
    naive = "Tue, 27 Oct 2099 21:00:00"
    assert retry_wait({"Retry-After": naive}) == MAX_WAIT


def test_problem_json_becomes_api_error(api: FakeAPI) -> None:
    api.queue(
        Reply(
            404,
            {
                "type": "https://coworkingview.com/problems/not-found",
                "title": "Not found",
                "status": 404,
                "code": "NOT_FOUND",
                "detail": "No property with slug 'nope'.",
            },
        )
    )
    with pytest.raises(APIError) as info:
        api.client().space("nope")
    err = info.value
    assert (err.status, err.code, err.title) == (404, "NOT_FOUND", "Not found")
    assert err.detail == "No property with slug 'nope'."
    assert err.errors == []
    assert "404 NOT_FOUND: Not found" in str(err)
    assert "APIError(status=404" in repr(err)
    assert isinstance(err, CoworkingViewError)


def test_non_json_error_falls_back_to_reason(api: FakeAPI) -> None:
    api.queue(Reply(403, "<html>Forbidden</html>"))
    with pytest.raises(APIError) as info:
        api.client().rates()
    err = info.value
    assert (err.status, err.code, err.title, err.detail) == (403, "HTTP_403", "Forbidden", None)


def test_non_json_success_is_bad_response(api: FakeAPI) -> None:
    api.queue(Reply(200, "<html>maintenance</html>"))
    with pytest.raises(APIError) as info:
        api.client().rates()
    assert info.value.code == "BAD_RESPONSE"
    assert info.value.status == 200


def test_json_that_is_not_an_object_is_bad_response(api: FakeAPI) -> None:
    api.queue(Reply(200, [1, 2, 3]))
    with pytest.raises(APIError, match="BAD_RESPONSE"):
        api.client().rates()


@pytest.mark.parametrize(
    ("call", "body"),
    [
        ("rates", {"meta": {}}),
        ("rates", {"data": []}),
        ("spaces", {"data": {}}),
        ("space", {"data": []}),
    ],
)
def test_unexpected_envelope_is_bad_response(api: FakeAPI, call: str, body: object) -> None:
    api.queue(Reply(200, body))  # type: ignore[arg-type]
    client = api.client()
    method = (lambda: client.space("x")) if call == "space" else getattr(client, call)
    with pytest.raises(APIError) as info:
        method()
    assert info.value.code == "BAD_RESPONSE"


def test_unreachable_host_raises_base_error() -> None:
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]
    client = Client(base_url=f"http://127.0.0.1:{port}", timeout=2)
    with pytest.raises(CoworkingViewError, match="Could not reach") as info:
        client.rates()
    assert not isinstance(info.value, APIError)


def test_env_var_sets_base_url(monkeypatch: pytest.MonkeyPatch, api: FakeAPI) -> None:
    monkeypatch.setenv("COWORKINGVIEW_API_URL", api.url + "/")
    client = Client()
    assert client.base_url == api.url
    client._transport._sleep = api.sleeps.append
    api.queue(Reply(body=RATES_OK))
    client.rates()
    assert api.requests[0].path == "/v1/market/rates"


def test_explicit_base_url_beats_env(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("COWORKINGVIEW_API_URL", "http://env.invalid")
    assert Client(base_url="http://arg.invalid").base_url == "http://arg.invalid"
    monkeypatch.delenv("COWORKINGVIEW_API_URL")
    assert Client().base_url == "https://api.coworkingview.com"


def test_client_properties_and_repr() -> None:
    client = Client(base_url="http://x.invalid", timeout=5)
    assert client.timeout == 5.0
    assert client.user_agent.startswith("coworkingview-python/")
    assert repr(client) == "Client(base_url='http://x.invalid', timeout=5.0)"


@pytest.mark.parametrize("timeout", [0, -1, "20", True])
def test_bad_timeout(timeout: object) -> None:
    with pytest.raises(ValueError, match="timeout"):
        Client(timeout=timeout)  # type: ignore[arg-type]
