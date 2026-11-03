"""Connection resolution for CoworkingViewHook."""

from __future__ import annotations

import os
from unittest.mock import MagicMock, patch

import pytest
from airflow.exceptions import AirflowNotFoundException

from coworkingview_provider.client import ENV_BASE_URL
from coworkingview_provider.exceptions import CoworkingViewError
from coworkingview_provider.hooks.coworkingview import CoworkingViewHook
from tests.support import berlin_rates, json_response


def _conn(host: str | None = None):
    connection = MagicMock()
    connection.host = host
    connection.password = None
    return connection


def test_missing_connection_uses_the_public_api(monkeypatch):
    monkeypatch.delenv(ENV_BASE_URL, raising=False)
    seen: dict = {}

    def _open(request, timeout=None):
        seen["url"] = request.full_url
        return json_response(berlin_rates())

    hook = CoworkingViewHook()
    with (
        patch.object(hook, "get_connection", side_effect=AirflowNotFoundException("missing")),
        patch("urllib.request.urlopen", side_effect=_open),
    ):
        payload = hook.get_city_rates(city="berlin")
    assert seen["url"].startswith("https://api.coworkingview.com/v1/market/rates?")
    assert payload["city"] == "berlin"
    ok, message = hook.test_connection()
    assert ok is True
    assert "berlin" in message


def test_host_overrides_the_environment(monkeypatch):
    monkeypatch.setenv(ENV_BASE_URL, "https://from-env.test")
    seen: dict = {}

    def _open(request, timeout=None):
        seen["url"] = request.full_url
        return json_response(berlin_rates())

    hook = CoworkingViewHook()
    with (
        patch.object(hook, "get_connection", return_value=_conn("https://from-connection.test/")),
        patch("urllib.request.urlopen", side_effect=_open),
    ):
        hook.get_city_rates(city="berlin")
    assert seen["url"].startswith("https://from-connection.test/v1/market/rates?")


def test_environment_is_used_when_the_connection_has_no_host(monkeypatch):
    monkeypatch.setenv(ENV_BASE_URL, "https://from-env.test")
    seen: dict = {}

    def _open(request, timeout=None):
        seen["url"] = request.full_url
        return json_response(berlin_rates())

    hook = CoworkingViewHook()
    with (
        patch.object(hook, "get_connection", return_value=_conn("  ")),
        patch("urllib.request.urlopen", side_effect=_open),
    ):
        hook.get_city_rates(city="berlin")
    assert seen["url"].startswith("https://from-env.test/v1/market/rates?")
    assert os.environ[ENV_BASE_URL] == "https://from-env.test"


def test_file_url_is_refused_before_urlopen():
    hook = CoworkingViewHook()
    with (
        patch.object(hook, "get_connection", return_value=_conn("file:///etc/passwd")),
        patch("urllib.request.urlopen") as urlopen,
        pytest.raises(CoworkingViewError, match="http"),
    ):
        hook.get_city_rates(city="berlin")
    urlopen.assert_not_called()


def test_ui_hides_credentials_and_connection_type_is_stable():
    behaviour = CoworkingViewHook.get_ui_field_behaviour()
    assert "password" in behaviour["hidden_fields"]
    assert "login" in behaviour["hidden_fields"]
    assert behaviour["placeholders"]["host"] == "https://api.coworkingview.com"
    assert CoworkingViewHook.conn_type == "coworkingview"
    assert CoworkingViewHook.default_conn_name == "coworkingview_default"
    assert CoworkingViewHook.conn_name_attr == "coworkingview_conn_id"


def test_test_connection_reports_an_api_error():
    hook = CoworkingViewHook()
    with patch.object(hook, "get_city_rates", side_effect=CoworkingViewError("nope")):
        ok, message = hook.test_connection()
    assert ok is False
    assert message == "nope"
