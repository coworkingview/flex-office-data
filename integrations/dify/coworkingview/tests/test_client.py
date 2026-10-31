"""Unit tests with mocked CoworkingView responses. No network."""

from __future__ import annotations

import email.message
import io
import json
import unittest
import urllib.error
import urllib.parse
from pathlib import Path

from coworkingview_client import (
    APIError,
    Client,
    CoworkingViewError,
    render_cities,
    render_workspaces,
    workspace_type_codes,
)

ROOT = Path(__file__).resolve().parents[1]
PRICE_SENTINEL = 424242


def _json_bytes(payload: dict) -> bytes:
    return json.dumps(payload).encode()


class FakeResponse:
    def __init__(self, body: bytes, status: int = 200, headers: dict | None = None) -> None:
        self.status = status
        self.headers = headers or {}
        self._body = body

    def read(self, n: int = -1) -> bytes:
        if n is None or n < 0:
            data, self._body = self._body, b""
            return data
        data, self._body = self._body[:n], self._body[n:]
        return data

    def close(self) -> None:
        return None


def http_error(status: int, body: dict | str, headers: dict | None = None) -> urllib.error.HTTPError:
    hdrs = email.message.EmailMessage()
    for key, value in (headers or {}).items():
        hdrs[key] = value
    raw = body if isinstance(body, str) else json.dumps(body)
    return urllib.error.HTTPError(
        "https://api.coworkingview.com/v1/properties",
        status,
        "error",
        hdrs,
        io.BytesIO(raw.encode()),
    )


class Script:
    def __init__(self, items: list) -> None:
        self.items = list(items)
        self.calls: list[urllib.request.Request] = []

    def __call__(self, request: urllib.request.Request, timeout: float):
        self.calls.append(request)
        item = self.items.pop(0)
        if isinstance(item, Exception):
            raise item
        return item


def client(script: Script, sleeps: list | None = None) -> Client:
    return Client(
        base_url="https://api.coworkingview.com",
        opener=script,
        sleeper=(sleeps.append if sleeps is not None else (lambda _seconds: None)),
    )


def search_card() -> dict:
    return {
        "slug": "sankt-oberholz-rosenthaler-berlin",
        "title": "St. Oberholz Coworking Berlin Mitte – Rosenthaler Straße",
        "countryCode": "DE",
        "city": {"slug": "berlin", "name": "Berlin"},
        "zone": {"slug": "mitte", "name": "Mitte"},
        "operator": {"slug": "sankt-oberholz", "name": "St. Oberholz", "logo": {"url": "https://example.com/logo.png"}},
        "fromPrice": {"amount": PRICE_SENTINEL, "currency": "EUR"},
        "excerpt": "Example description used as a test fixture.",
        "images": [{"url": "https://example.com/image.webp"}],
        "featured": True,
    }


def detail_body(web_url: str | None = None) -> dict:
    return {
        "data": {
            "slug": "sankt-oberholz-rosenthaler-berlin",
            "title": "St. Oberholz Coworking Berlin Mitte – Rosenthaler Straße",
            "city": {"slug": "berlin", "name": "Berlin"},
            "zone": {"slug": "mitte", "name": "Mitte"},
            "operator": {"name": "St. Oberholz"},
            "address": "Rosenthaler Straße 72a, 10119 Berlin, Germany",
            "description": "Example description used as a test fixture.",
            "images": [{"url": "https://example.com/image.webp"}],
            "fromPrice": {"amount": PRICE_SENTINEL, "currency": "EUR"},
            "pricingOptions": [
                {
                    "optionType": "flex_desk",
                    "title": "Coworking Membership – Flex Desk",
                    "price": {"amount": PRICE_SENTINEL, "currency": "EUR"},
                    "priceOnRequest": False,
                    "billingPeriod": "month",
                },
                {"optionType": "private_office", "title": "Private Team Room", "priceOnRequest": True, "billingPeriod": "month"},
            ],
            "webUrl": web_url
            or "https://coworkingview.com/en/workspace/sankt-oberholz-rosenthaler-berlin",
        },
        "meta": {
            "citation": {"text": "Source: CoworkingView — listing."},
            "catalogueNotice": "You may link to listing pages.",
        },
    }


class SearchTests(unittest.TestCase):
    def test_search_returns_name_city_type_and_listing_url_without_invented_address_or_price(self) -> None:
        script = Script(
            [
                FakeResponse(
                    _json_bytes(
                        {
                            "data": [search_card()],
                            "meta": {
                                "pagination": {"total": 12},
                                "citation": {"text": "Source: CoworkingView."},
                                "catalogueNotice": "You may link to listing pages.",
                            },
                        }
                    )
                )
            ]
        )
        result = client(script).search_workspaces("Berlin", "meeting room", locale="en", limit=10)
        self.assertEqual(len(script.calls), 1)
        query = urllib.parse.parse_qs(urllib.parse.urlsplit(script.calls[0].full_url).query)
        self.assertEqual(query["city"], ["berlin"])
        self.assertEqual(query["pricingOptionType"], ["meeting_room"])
        self.assertEqual(query["pageSize"], ["10"])
        workspace = result["workspaces"][0]
        self.assertEqual(workspace["name"], "St. Oberholz Coworking Berlin Mitte – Rosenthaler Straße")
        self.assertEqual(workspace["city"], "Berlin")
        self.assertIsNone(workspace["address"])
        self.assertEqual(workspace["zone"], "Mitte")
        self.assertEqual(workspace["type"], ["meeting_room"])
        self.assertEqual(
            workspace["url"],
            "https://coworkingview.com/en/workspace/sankt-oberholz-rosenthaler-berlin",
        )
        self.assertNotIn("www.", workspace["url"])
        encoded = json.dumps(result)
        self.assertNotIn(str(PRICE_SENTINEL), encoded)
        self.assertNotIn("fromPrice", encoded)
        self.assertNotIn("Example description", encoded)
        self.assertNotIn("example.com", encoded)
        self.assertEqual(result["total"], 12)
        self.assertIn("Source: CoworkingView.", result["citation"])
        text = render_workspaces(result)
        self.assertIn("street address not in this response", text)
        self.assertNotIn(str(PRICE_SENTINEL), text)

    def test_search_without_type_leaves_type_null_and_does_not_fetch_each_listing(self) -> None:
        cards = [search_card(), {**search_card(), "slug": "second-space", "title": "Second"}]
        script = Script([FakeResponse(_json_bytes({"data": cards, "meta": {}}))])
        result = client(script).search_workspaces(city="abu dhabi")
        self.assertEqual(len(script.calls), 1)
        self.assertNotIn("pricingOptionType", script.calls[0].full_url)
        self.assertEqual(urllib.parse.parse_qs(urllib.parse.urlsplit(script.calls[0].full_url).query)["city"], ["abu-dhabi"])
        self.assertIsNone(result["workspaces"][0]["type"])
        self.assertIsNone(result["workspaces"][0]["address"])
        self.assertEqual(len(result["workspaces"]), 2)

    def test_german_and_spanish_listing_paths(self) -> None:
        expected = {
            "de_DE": "https://coworkingview.com/de/buero/sankt-oberholz-rosenthaler-berlin",
            "es-ES": "https://coworkingview.com/es/oficina/sankt-oberholz-rosenthaler-berlin",
        }
        for locale, url in expected.items():
            script = Script([FakeResponse(_json_bytes({"data": [search_card()], "meta": {}}))])
            result = client(script).search_workspaces("berlin", locale=locale)
            self.assertEqual(result["workspaces"][0]["url"], url)

    def test_invalid_type_does_not_call_the_api(self) -> None:
        script = Script([])
        with self.assertRaises(CoworkingViewError):
            client(script).search_workspaces("berlin", "coworking")
        self.assertEqual(script.calls, [])

    def test_limit_above_20_does_not_call_the_api(self) -> None:
        script = Script([])
        with self.assertRaises(CoworkingViewError):
            client(script).search_workspaces("berlin", limit=21)
        self.assertEqual(script.calls, [])


class DetailTests(unittest.TestCase):
    def test_detail_returns_published_address_and_types_and_drops_prices(self) -> None:
        script = Script([FakeResponse(_json_bytes(detail_body()))])
        result = client(script).get_workspace("sankt-oberholz-rosenthaler-berlin")
        self.assertEqual(len(script.calls), 1)
        self.assertTrue(script.calls[0].full_url.endswith("/v1/properties/sankt-oberholz-rosenthaler-berlin?locale=en"))
        workspace = result["workspace"]
        self.assertEqual(workspace["address"], "Rosenthaler Straße 72a, 10119 Berlin, Germany")
        self.assertEqual(workspace["type"], ["flex_desk", "private_office"])
        self.assertEqual(workspace["url"], "https://coworkingview.com/en/workspace/sankt-oberholz-rosenthaler-berlin")
        self.assertEqual(workspace["operator"], "St. Oberholz")
        encoded = json.dumps(result)
        self.assertNotIn(str(PRICE_SENTINEL), encoded)
        self.assertNotIn("price", encoded)
        self.assertNotIn("Example description", encoded)
        self.assertIn("Source: CoworkingView", result["citation"])

    def test_www_web_url_is_rewritten_and_foreign_web_url_is_not_used(self) -> None:
        script = Script(
            [
                FakeResponse(
                    _json_bytes(
                        detail_body("https://www.coworkingview.com/en/workspace/sankt-oberholz-rosenthaler-berlin")
                    )
                )
            ]
        )
        result = client(script).get_workspace("sankt-oberholz-rosenthaler-berlin", locale="en")
        self.assertEqual(
            result["workspace"]["url"],
            "https://coworkingview.com/en/workspace/sankt-oberholz-rosenthaler-berlin",
        )
        foreign = detail_body("https://evil.example/phish")
        script = Script([FakeResponse(_json_bytes(foreign))])
        result = client(script).get_workspace("sankt-oberholz-rosenthaler-berlin", locale="de")
        self.assertEqual(
            result["workspace"]["url"],
            "https://coworkingview.com/de/buero/sankt-oberholz-rosenthaler-berlin",
        )

    def test_missing_address_stays_null(self) -> None:
        body = detail_body()
        body["data"].pop("address")
        script = Script([FakeResponse(_json_bytes(body))])
        workspace = client(script).get_workspace("sankt-oberholz-rosenthaler-berlin")["workspace"]
        self.assertIsNone(workspace["address"])
        self.assertEqual(workspace["zone"], "Mitte")
        self.assertNotIn("Mitte", workspace["address"] or "")

    def test_bad_slug_does_not_call_the_api(self) -> None:
        script = Script([])
        with self.assertRaises(CoworkingViewError):
            client(script).get_workspace("../etc/passwd")
        self.assertEqual(script.calls, [])


class CityTests(unittest.TestCase):
    def test_cities_come_from_the_places_index_only(self) -> None:
        script = Script(
            [
                FakeResponse(
                    _json_bytes(
                        {
                            "data": {
                                "cities": [
                                    {
                                        "slug": "paris",
                                        "name": "Paris ",
                                        "countryCode": "FR",
                                        "propertyCount": 0,
                                        "center": {"lat": 0, "lng": 0},
                                        "icon": {"url": "https://example.com/paris.png"},
                                    },
                                    {
                                        "slug": "berlin",
                                        "name": "Berlin",
                                        "countryCode": "DE",
                                        "propertyCount": 85,
                                    },
                                    {"name": "Missing slug"},
                                ]
                            },
                            "meta": {"contractVersion": "1.0.0"},
                        }
                    )
                )
            ]
        )
        result = client(script).list_cities()
        self.assertEqual(len(script.calls), 1)
        self.assertIn("/v1/geo/bootstrap", script.calls[0].full_url)
        self.assertEqual(
            result["cities"],
            [
                {"slug": "berlin", "name": "Berlin", "country_code": "DE", "property_count": 85},
                {"slug": "paris", "name": "Paris", "country_code": "FR", "property_count": 0},
            ],
        )
        self.assertNotIn("example.com", json.dumps(result))
        self.assertIsNone(result["citation"])
        text = render_cities(result)
        self.assertIn("berlin", text)
        self.assertIn("85", text)

    def test_country_filter(self) -> None:
        script = Script(
            [
                FakeResponse(
                    _json_bytes(
                        {
                            "data": {
                                "cities": [
                                    {"slug": "berlin", "name": "Berlin", "countryCode": "DE", "propertyCount": 1},
                                    {"slug": "madrid", "name": "Madrid", "countryCode": "ES", "propertyCount": 2},
                                ]
                            },
                            "meta": {},
                        }
                    )
                )
            ]
        )
        result = client(script).list_cities(country="es")
        self.assertEqual([row["slug"] for row in result["cities"]], ["madrid"])


class HttpTests(unittest.TestCase):
    def test_retry_once_on_429_then_succeeds(self) -> None:
        sleeps: list[float] = []
        ok = FakeResponse(_json_bytes({"data": [search_card()], "meta": {}}))
        script = Script([http_error(429, {"code": "RATE_LIMITED", "title": "Slow down", "detail": "wait"}, {"Retry-After": "0"}), ok])
        result = client(script, sleeps).search_workspaces("berlin")
        self.assertEqual(len(script.calls), 2)
        self.assertEqual(sleeps, [0.0])
        self.assertEqual(len(result["workspaces"]), 1)

    def test_400_does_not_retry(self) -> None:
        script = Script(
            [
                http_error(
                    400,
                    {"code": "VALIDATION_FAILED", "title": "Invalid", "detail": "city is unknown"},
                )
            ]
        )
        with self.assertRaises(APIError) as caught:
            client(script).search_workspaces("berlin")
        self.assertEqual(len(script.calls), 1)
        self.assertEqual(caught.exception.status, 400)
        self.assertEqual(caught.exception.code, "VALIDATION_FAILED")
        self.assertIn("city is unknown", str(caught.exception))

    def test_second_5xx_is_an_error(self) -> None:
        script = Script(
            [
                http_error(503, {"code": "UPSTREAM_UNAVAILABLE", "title": "Down", "detail": "try later"}),
                http_error(503, {"code": "UPSTREAM_UNAVAILABLE", "title": "Down", "detail": "try later"}),
            ]
        )
        with self.assertRaises(APIError) as caught:
            client(script).search_workspaces("berlin")
        self.assertEqual(len(script.calls), 2)
        self.assertEqual(caught.exception.code, "UPSTREAM_UNAVAILABLE")

    def test_connection_error_does_not_retry(self) -> None:
        script = Script([urllib.error.URLError("timed out")])
        with self.assertRaises(CoworkingViewError) as caught:
            client(script).list_cities()
        self.assertEqual(len(script.calls), 1)
        self.assertIn("could not be reached", str(caught.exception))

    def test_non_json_body_is_an_error(self) -> None:
        script = Script([FakeResponse(b"<html>nope</html>")])
        with self.assertRaises(APIError) as caught:
            client(script).list_cities()
        self.assertEqual(caught.exception.code, "BAD_RESPONSE")


class PackageShapeTests(unittest.TestCase):
    def test_manifest_marketplace_fields(self) -> None:
        text = (ROOT / "manifest.yaml").read_text(encoding="utf-8")
        self.assertIn("author: coworkingview", text)
        self.assertIn("name: coworkingview", text)
        self.assertIn("en_US: CoworkingView", text)
        self.assertIn("repo: https://github.com/coworkingview/flex-office-data", text)
        self.assertIn("homepage: https://coworkingview.com", text)
        self.assertIn("contact: info@coworkingview.com", text)
        self.assertNotIn("www.coworkingview.com", text)
        self.assertNotIn("de_DE:", text)
        self.assertNotIn("es_ES:", text)

    def test_tool_options_match_the_client(self) -> None:
        text = (ROOT / "tools" / "search_workspaces.yaml").read_text(encoding="utf-8")
        for code in workspace_type_codes():
            self.assertIn(f"value: {code}", text)

    def test_readme_links_the_site_without_www(self) -> None:
        text = (ROOT / "README.md").read_text(encoding="utf-8")
        self.assertIn("https://coworkingview.com", text)
        self.assertIn("https://github.com/coworkingview/flex-office-data", text)
        self.assertNotIn("https://www.coworkingview.com", text)

    def test_sdk_loads_the_provider_and_tools(self) -> None:
        try:
            from dify_plugin import Tool
            from dify_plugin.core.utils.yaml_loader import load_yaml_file
            from dify_plugin.entities.tool import ToolProviderConfiguration
        except ImportError:
            self.skipTest("dify_plugin is not installed")
        import os

        cwd = os.getcwd()
        os.chdir(ROOT)
        try:
            data = load_yaml_file("provider/coworkingview.yaml")
            provider = ToolProviderConfiguration(**data)
        finally:
            os.chdir(cwd)
        self.assertEqual(
            [tool.identity.name for tool in provider.tools],
            ["search_workspaces", "get_workspace", "list_cities"],
        )
        from tools.get_workspace import GetWorkspaceTool
        from tools.list_cities import ListCitiesTool
        from tools.search_workspaces import SearchWorkspacesTool

        self.assertTrue(issubclass(SearchWorkspacesTool, Tool))
        self.assertTrue(issubclass(GetWorkspaceTool, Tool))
        self.assertTrue(issubclass(ListCitiesTool, Tool))


if __name__ == "__main__":
    unittest.main()
