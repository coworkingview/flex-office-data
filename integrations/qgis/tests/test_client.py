# -*- coding: utf-8 -*-
"""Tests for the CoworkingView API client used by the QGIS plugin."""

import ast
import json
import unittest
from pathlib import Path

from client import (
    MAX_SPACES,
    VERSION,
    Client,
    CoworkingViewError,
    Cancelled,
    accepted_listing_url,
    cities_from_bootstrap,
    format_types,
    listing_url,
    status_message,
)

FIXTURES = Path(__file__).resolve().parents[3] / "spec" / "fixtures"
PLUGIN = Path(__file__).resolve().parents[1] / "coworkingview"


def _body(payload, status=200, headers=None):
    raw = payload if isinstance(payload, bytes) else json.dumps(payload).encode("utf-8")
    return status, headers or {}, raw


class Clock:
    def __init__(self):
        self.t = 0.0
        self.sleeps = []

    def now(self):
        return self.t

    def sleep(self, seconds):
        self.sleeps.append(seconds)
        self.t += seconds


class Script:
    """Return scripted HTTP responses and record the URLs."""

    def __init__(self, handler):
        self.handler = handler
        self.urls = []
        self.headers = []

    def __call__(self, url, headers, timeout):
        self.urls.append(url)
        self.headers.append(headers)
        return self.handler(url)


def _client(handler, **kwargs):
    clock = kwargs.pop("clock", Clock())
    return Client(
        base_url="https://api.example.test",
        request_fn=Script(handler) if not isinstance(handler, Script) else handler,
        sleep=clock.sleep,
        now=clock.now,
        min_interval=kwargs.pop("min_interval", 0),
        **kwargs,
    ), clock


class ClientTests(unittest.TestCase):
    def test_import_does_not_request(self):
        source = (PLUGIN / "client.py").read_text(encoding="utf-8")
        tree = ast.parse(source)
        for node in ast.walk(tree):
            if isinstance(node, ast.Import):
                names = [alias.name for alias in node.names]
            elif isinstance(node, ast.ImportFrom):
                names = [node.module or ""]
            else:
                continue
            for name in names:
                self.assertFalse(name.startswith("qgis"), name)

    def test_version_constant(self):
        self.assertEqual(VERSION, "0.1.0")
        self.assertEqual(MAX_SPACES, 200)

    def test_listing_url_has_no_www(self):
        url = listing_url("sankt-oberholz-rosenthaler-berlin")
        self.assertEqual(
            url,
            "https://coworkingview.com/en/workspace/sankt-oberholz-rosenthaler-berlin",
        )
        self.assertNotIn("www.", url)

    def test_rejects_off_site_listing_url(self):
        fallback = listing_url("space")
        self.assertEqual(accepted_listing_url("https://evil.example/phish", "space"), fallback)
        insecure = "http://coworkingview.com/en/workspace/space"
        self.assertEqual(accepted_listing_url(insecure, "space"), fallback)
        official = "https://coworkingview.com/en/workspace/space"
        self.assertEqual(accepted_listing_url(official, "space"), official)

    def test_format_types_orders_and_dedupes(self):
        self.assertEqual(
            format_types(["event_space", "event_space", "flex_desk"]),
            "Flex desk, Event space",
        )
        self.assertEqual(format_types(["not_a_product"]), "not_a_product")
        self.assertIsNone(format_types([]))

    def test_cities_skip_empty_and_strip_names(self):
        payload = {
            "data": {
                "cities": [
                    {
                        "slug": "paris",
                        "name": "Paris ",
                        "countryCode": "fr",
                        "propertyCount": 0,
                    },
                    {
                        "slug": "berlin",
                        "name": " Berlin ",
                        "countryCode": "DE",
                        "propertyCount": 2,
                    },
                ]
            }
        }
        cities = cities_from_bootstrap(payload)
        self.assertEqual([city.slug for city in cities], ["berlin"])
        self.assertEqual(cities[0].name, "Berlin")
        self.assertEqual(cities[0].country_code, "DE")
        self.assertEqual(cities[0].property_count, 2)

    def test_city_fallback_uses_market_rates(self):
        rates = {
            "data": {
                "cities": [
                    {
                        "city": {"slug": "madrid", "name": "Madrid"},
                        "countryCode": "ES",
                        "propertyCount": 4,
                    }
                ]
            }
        }

        def handler(url):
            if url.endswith("/v1/geo/bootstrap?locale=en"):
                return _body({"title": "Down", "code": "INTERNAL_ERROR"}, status=500)
            if url.endswith("/v1/market/rates?locale=en"):
                return _body(rates)
            raise AssertionError(url)

        client, _clock = _client(handler)
        cities = client.list_cities()
        self.assertEqual(cities[0].slug, "madrid")
        self.assertEqual(cities[0].name, "Madrid")

    def test_retries_429_once(self):
        clock = Clock()
        calls = {"n": 0}

        def handler(url):
            calls["n"] += 1
            if calls["n"] == 1:
                return _body(
                    {"title": "Slow down", "code": "RATE_LIMITED", "detail": "Wait"},
                    status=429,
                    headers={"Retry-After": "1"},
                )
            return _body(
                {
                    "data": {
                        "cities": [
                            {
                                "slug": "hamburg",
                                "name": "Hamburg",
                                "countryCode": "DE",
                                "propertyCount": 1,
                            }
                        ]
                    }
                }
            )

        script = Script(handler)
        client = Client(
            base_url="https://api.example.test",
            request_fn=script,
            sleep=clock.sleep,
            now=clock.now,
            min_interval=0,
        )
        cities = client.list_cities()
        self.assertEqual(cities[0].slug, "hamburg")
        self.assertEqual(calls["n"], 2)
        self.assertIn(1.0, clock.sleeps)
        self.assertEqual(script.headers[0]["Accept"], "application/json")
        self.assertIn("coworkingview-qgis/0.1.0", script.headers[0]["User-Agent"])

    def test_does_not_retry_400(self):
        calls = {"n": 0}

        def handler(url):
            calls["n"] += 1
            return _body(
                {"title": "Bad request", "code": "VALIDATION_FAILED", "detail": "city"},
                status=400,
            )

        client, _clock = _client(handler)
        with self.assertRaises(CoworkingViewError) as caught:
            client.list_cities()
        # 400 is not retried. The places index fails, then the price-index
        # city list is tried once and fails the same way.
        self.assertEqual(calls["n"], 2)
        self.assertEqual(caught.exception.status, 400)
        self.assertEqual(caught.exception.code, "VALIDATION_FAILED")
        self.assertIn("city", str(caught.exception))

    def test_bad_json(self):
        def handler(url):
            return 200, {}, b"not-json"

        client, _clock = _client(handler)
        with self.assertRaises(CoworkingViewError) as caught:
            client.list_cities()
        self.assertEqual(caught.exception.code, "BAD_RESPONSE")

    def test_connection_error(self):
        def handler(url):
            raise OSError("timed out")

        client, _clock = _client(handler)
        with self.assertRaises(CoworkingViewError) as caught:
            client.list_cities()
        self.assertIn("Could not reach the CoworkingView API", str(caught.exception))

    def test_bad_city_does_not_call_the_network(self):
        def handler(url):
            raise AssertionError(url)

        client, _clock = _client(handler)
        with self.assertRaises(CoworkingViewError) as caught:
            client.load_spaces("../berlin", "Berlin")
        self.assertEqual(caught.exception.code, "BAD_CITY")

    def test_bad_base_url(self):
        with self.assertRaises(CoworkingViewError):
            Client(base_url="file:///tmp", request_fn=lambda *args: None, min_interval=0)

    def test_berlin_fixtures_fill_address_type_and_url(self):
        listed = json.loads((FIXTURES / "properties_berlin.json").read_text(encoding="utf-8"))
        detail = json.loads((FIXTURES / "property_detail.json").read_text(encoding="utf-8"))
        listed["meta"]["pagination"] = {"page": 1, "pageSize": 3, "total": 3, "pageCount": 1}

        def handler(url):
            if "/v1/properties?" in url:
                self.assertIn("city=berlin", url)
                self.assertIn("pricingOptionType=flex_desk", url)
                self.assertIn("sortBy=date-desc", url)
                self.assertNotIn("minPrice", url)
                return _body(listed)
            slug = url.split("/v1/properties/")[1].split("?")[0]
            if slug == "sankt-oberholz-rosenthaler-berlin":
                return _body(detail)
            return _body(
                {
                    "data": {
                        "slug": slug,
                        "title": slug,
                        "address": None,
                        "webUrl": "https://example.com/not-the-listing",
                        "pricingOptions": [
                            {
                                "optionType": "flex_desk",
                                "title": "Flex",
                                "priceOnRequest": True,
                                "billingPeriod": "month",
                            }
                        ],
                    },
                    "meta": {},
                }
            )

        client, _clock = _client(handler)
        result = client.load_spaces("berlin", "Berlin", pricing_option_type="flex_desk")
        self.assertEqual(len(result.workspaces), 3)
        self.assertFalse(result.truncated)
        by_slug = {space.slug: space for space in result.workspaces}
        oberholz = by_slug["sankt-oberholz-rosenthaler-berlin"]
        self.assertEqual(oberholz.address, "Rosenthaler Straße 72a, 10119 Berlin, Germany")
        self.assertEqual(oberholz.city, "Berlin")
        self.assertEqual(oberholz.lat, 52.5294539)
        self.assertEqual(oberholz.lng, 13.4018374)
        self.assertEqual(
            oberholz.workspace_type,
            "Flex desk, Dedicated desk, Private office, Meeting room, Virtual office",
        )
        self.assertEqual(
            oberholz.url,
            "https://coworkingview.com/en/workspace/sankt-oberholz-rosenthaler-berlin",
        )
        self.assertIn("Coworking spaces in Berlin", result.citation)
        self.assertTrue(result.notice.startswith("Catalogue content"))
        self.assertNotIn("St. Oberholz Coworking Berlin Mitte", result.citation)
        other = by_slug["regus-charlottenburg-berlin"]
        self.assertIsNone(other.address)
        self.assertEqual(other.workspace_type, "Flex desk")
        self.assertEqual(
            other.url,
            "https://coworkingview.com/en/workspace/regus-charlottenburg-berlin",
        )
        for space in result.workspaces:
            blob = " ".join(
                str(getattr(space, name))
                for name in ("name", "city", "address", "workspace_type", "url", "slug")
            )
            self.assertNotIn("209", blob)
            self.assertNotIn("example.com", blob)
            self.assertNotIn("Example description", blob)
        self.assertEqual(status_message(result), "Added 3 Flex desk workspaces in Berlin.")

    def test_skips_null_island_and_counts_detail_failure(self):
        def handler(url):
            if "/v1/properties?" in url:
                return _body(
                    {
                        "data": [
                            {
                                "slug": "no-geo",
                                "title": "No geo",
                                "coordinates": {"lat": 0, "lng": 0},
                                "city": {"slug": "berlin", "name": "Berlin"},
                            },
                            {
                                "slug": "kept",
                                "title": "Kept",
                                "coordinates": {"lat": 52.5, "lng": 13.4},
                                "city": {"slug": "berlin", "name": "Berlin"},
                            },
                        ],
                        "meta": {
                            "pagination": {"total": 2, "pageCount": 1},
                            "citation": {"text": "Source: CoworkingView."},
                            "catalogueNotice": "You may link to listing pages.",
                        },
                    }
                )
            if url.endswith("/kept?locale=en"):
                return _body({"title": "Missing", "code": "NOT_FOUND"}, status=404)
            return _body({"data": {}}, status=200)

        client, _clock = _client(handler)
        result = client.load_spaces("berlin", "Berlin")
        self.assertEqual([space.slug for space in result.workspaces], ["kept"])
        self.assertIsNone(result.workspaces[0].address)
        self.assertIsNone(result.workspaces[0].workspace_type)
        self.assertEqual(result.skipped, 1)
        self.assertEqual(result.detail_failures, 1)
        self.assertIn("left off the map", status_message(result))
        self.assertIn("could not be read in full", status_message(result))

    def test_cap_stops_at_max_spaces(self):
        def handler(url):
            if "/v1/properties?" in url:
                rows = [
                    {
                        "slug": "space-{0}".format(index),
                        "title": "Space {0}".format(index),
                        "coordinates": {"lat": 52.5, "lng": 13.4 + index / 100.0},
                        "city": {"slug": "berlin", "name": "Berlin"},
                    }
                    for index in range(3)
                ]
                return _body(
                    {
                        "data": rows,
                        "meta": {"pagination": {"total": 3, "pageCount": 1}},
                    }
                )
            slug = url.split("/v1/properties/")[1].split("?")[0]
            return _body(
                {
                    "data": {
                        "slug": slug,
                        "title": slug,
                        "address": "Street",
                        "pricingOptions": [],
                        "webUrl": "https://coworkingview.com/en/workspace/{0}".format(slug),
                    }
                }
            )

        client, _clock = _client(handler, max_spaces=1)
        result = client.load_spaces("berlin", "Berlin")
        self.assertEqual(len(result.workspaces), 1)
        self.assertTrue(result.truncated)
        self.assertIn("Showing 1 of 3", status_message(result))
        self.assertNotIn("at most", status_message(result))

    def test_cancel_before_details(self):
        calls = {"n": 0}

        def handler(url):
            calls["n"] += 1
            return _body(
                {
                    "data": [
                        {
                            "slug": "kept",
                            "title": "Kept",
                            "coordinates": {"lat": 52.5, "lng": 13.4},
                        }
                    ],
                    "meta": {"pagination": {"total": 1, "pageCount": 1}},
                }
            )

        client, _clock = _client(handler)

        def should_cancel():
            return calls["n"] >= 1

        with self.assertRaises(Cancelled):
            client.load_spaces("berlin", "Berlin", should_cancel=should_cancel)
        self.assertEqual(calls["n"], 1)


if __name__ == "__main__":
    unittest.main()
