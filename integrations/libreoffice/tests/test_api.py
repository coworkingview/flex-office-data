"""Mapping and HTTP tests. No network. Payloads use the live field names."""

import json
import sys
import unittest
import urllib.error
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "pythonpath"))

import coworkingview_api as api

BERLIN = {
    "data": {
        "asOf": "2026-10-30T13:21:31.959Z",
        "attribution": (
            "Source: CoworkingView Price Index "
            "(https://www.coworkingview.com/en/tools/price-index), "
            "as of October 2026. Licensed under CC BY 4.0."
        ),
        "license": "CC-BY-4.0",
        "licenseUrl": "https://creativecommons.org/licenses/by/4.0/",
        "cities": [
            {
                "city": {"slug": "berlin", "name": "Berlin"},
                "countryCode": "DE",
                "currency": "EUR",
                "propertyCount": 85,
                "operatorCount": 48,
                "sampleSize": 85,
                "figures": [
                    {
                        "optionType": "flex_desk",
                        "median": {"amount": 214, "currency": "EUR"},
                        "p25": {"amount": 199, "currency": "EUR"},
                        "p75": {"amount": 292, "currency": "EUR"},
                        "sampleSize": 72,
                    },
                    {
                        "optionType": "fix_desk",
                        "median": {"amount": 310, "currency": "EUR"},
                        "p25": {"amount": 290, "currency": "EUR"},
                        "p75": {"amount": 421, "currency": "EUR"},
                        "sampleSize": 60,
                    },
                    {
                        "optionType": "private_office",
                        "median": {"amount": 480, "currency": "EUR"},
                        "p25": {"amount": 399, "currency": "EUR"},
                        "p75": {"amount": 550, "currency": "EUR"},
                        "sampleSize": 59,
                    },
                ],
                "byType": [
                    {
                        "optionType": "flex_desk",
                        "median": {"amount": 214, "currency": "EUR"},
                        "min": {"amount": 160, "currency": "EUR"},
                        "max": {"amount": 680, "currency": "EUR"},
                        "sampleSize": 99,
                    }
                ],
                "dayPass": {
                    "median": {"amount": 35, "currency": "EUR"},
                    "sampleSize": 59,
                },
                "meetingRoom": {
                    "median": {"amount": 32, "currency": "EUR"},
                    "sampleSize": 79,
                },
                "p25": {"amount": 219, "currency": "EUR"},
                "entryMedian": {"amount": 265, "currency": "EUR"},
                "buildings": [{"name": "should be dropped"}],
            }
        ],
    },
    "meta": {"contractVersion": "1.0.0"},
}


class Response:
    def __init__(self, status, body, headers=None):
        self.status = status
        self.headers = headers or {"Cache-Control": "public, max-age=600"}
        if isinstance(body, bytes):
            self._body = body
        else:
            self._body = json.dumps(body).encode("utf-8")

    def read(self, _size=-1):
        return self._body

    def getcode(self):
        return self.status

    def __enter__(self):
        return self

    def __exit__(self, *_args):
        return False


class FakeHTTP:
    def __init__(self, routes):
        self.routes = list(routes)
        self.urls = []
        self.agents = []

    def __call__(self, request, timeout=0):
        self.urls.append(request.full_url)
        self.agents.append(request.get_header("User-agent"))
        if not self.routes:
            raise AssertionError("unexpected request " + request.full_url)
        item = self.routes.pop(0)
        if isinstance(item, Exception):
            raise item
        return item


class MappingTest(unittest.TestCase):
    def test_source_is_the_fixed_credit_and_does_not_use_www(self):
        self.assertEqual(api.source(), "Data: CoworkingView https://coworkingview.com")
        self.assertNotIn("www.", api.source())

    def test_blank_city_is_berlin_and_names_become_slugs(self):
        self.assertEqual(api.city_slug(""), "berlin")
        self.assertEqual(api.city_slug(None), "berlin")
        self.assertEqual(api.city_slug("  Berlin "), "berlin")
        self.assertEqual(api.city_slug("Bad Homburg"), "bad-homburg")
        with self.assertRaises(api.CwvError):
            api.city_slug("München")

    def test_product_codes_follow_the_api_spellings(self):
        self.assertEqual(api.product_code("Flex Desk"), "flex_desk")
        self.assertEqual(api.product_code("day-pass"), "day_pass")
        self.assertEqual(api.product_code("meeting_room"), "meeting_room")

    def test_median_p25_and_min_come_from_the_objects_that_have_them(self):
        self.assertEqual(api.rate_amount(BERLIN, "berlin", "flex_desk", "median"), 214)
        self.assertEqual(api.rate_amount(BERLIN, "berlin", "flex_desk", "p25"), 199)
        self.assertEqual(api.rate_amount(BERLIN, "berlin", "flex_desk", "min"), 160)
        self.assertEqual(api.rate_amount(BERLIN, "berlin", "fix_desk", "median"), 310)
        self.assertEqual(api.rate_amount(BERLIN, "berlin", "private_office", "p75"), 550)

    def test_day_pass_and_meeting_room_use_their_own_objects(self):
        self.assertEqual(api.rate_amount(BERLIN, "berlin", "day_pass", "median"), 35)
        self.assertEqual(api.rate_amount(BERLIN, "berlin", "meeting_room", "median"), 32)
        with self.assertRaises(api.CwvError) as raised:
            api.rate_amount(BERLIN, "berlin", "day_pass", "p25")
        self.assertIn("not published", str(raised.exception))
        self.assertIn("median", str(raised.exception))

    def test_sample_size_prefers_figures_over_by_type(self):
        self.assertEqual(api.sample_size(BERLIN, "berlin", "flex_desk"), 72)
        self.assertEqual(api.sample_size(BERLIN, "berlin", "day_pass"), 59)

    def test_currency_asof_and_attribution_are_copied(self):
        self.assertEqual(api.currency_code(BERLIN, "berlin"), "EUR")
        self.assertEqual(api.as_of(BERLIN, "berlin"), "2026-10-30T13:21:31.959Z")
        text = api.attribution(BERLIN, "berlin")
        self.assertIn("CC BY 4.0", text)
        self.assertIn("www.coworkingview.com", text)

    def test_unknown_city_and_unknown_product_name_what_exists(self):
        empty = {"data": {"cities": [], "asOf": "2026-11-01T00:00:00Z"}}
        with self.assertRaises(api.CwvError) as raised:
            api.currency_code(empty, "not-a-city")
        self.assertIn("unknown city", str(raised.exception))
        with self.assertRaises(api.CwvError) as raised:
            api.rate_amount(BERLIN, "berlin", "hot_desk", "median")
        self.assertIn("flex_desk", str(raised.exception))
        self.assertIn("day_pass", str(raised.exception))
        self.assertNotIn("hot_desk", str(raised.exception).split("Available:", 1)[-1])

    def test_spaces_uses_pagination_total_not_property_count(self):
        http = FakeHTTP(
            [
                Response(200, BERLIN),
                Response(
                    200,
                    {
                        "data": [{"title": "operator listing"}],
                        "meta": {"pagination": {"total": 143, "page": 1, "pageSize": 1}},
                    },
                    headers={"Cache-Control": "public, max-age=300"},
                ),
            ]
        )
        client = api.Client(urlopen=http, sleep=lambda _seconds: None)
        self.assertEqual(api.spaces(client, "Berlin"), 143)
        self.assertIn("city=berlin", http.urls[0])
        self.assertIn("locale=en", http.urls[0])
        self.assertIn("/v1/market/rates", http.urls[0])
        self.assertIn("/v1/properties", http.urls[1])
        self.assertIn("pageSize=1", http.urls[1])
        self.assertIn("page=1", http.urls[1])
        cached = json.dumps(client._cache)
        self.assertNotIn("operator listing", cached)
        self.assertNotIn("should be dropped", cached)
        self.assertEqual(http.agents[0], api.USER_AGENT)

    def test_unknown_city_does_not_request_the_catalogue(self):
        http = FakeHTTP([Response(200, {"data": {"cities": [], "asOf": "t"}})])
        client = api.Client(urlopen=http, sleep=lambda _seconds: None)
        with self.assertRaises(api.CwvError):
            api.spaces(client, "nope")
        self.assertEqual(len(http.urls), 1)
        self.assertIn("/v1/market/rates", http.urls[0])

    def test_cache_and_single_retry(self):
        sleeps = []
        http = FakeHTTP(
            [
                Response(500, {"title": "busy", "code": "HTTP_500"}, headers={}),
                Response(200, BERLIN, headers={"Cache-Control": "max-age=600"}),
            ]
        )
        clock = {"now": 0.0}
        client = api.Client(
            urlopen=http,
            sleep=sleeps.append,
            clock=lambda: clock["now"],
        )
        self.assertEqual(api.currency(client, "berlin"), "EUR")
        self.assertEqual(sleeps, [2.0])
        self.assertEqual(api.currency(client, "berlin"), "EUR")
        self.assertEqual(len(http.urls), 2)
        clock["now"] = 601.0
        http.routes.append(Response(200, BERLIN))
        self.assertEqual(api.currency(client, "berlin"), "EUR")
        self.assertEqual(len(http.urls), 3)

    def test_validation_error_is_not_retried(self):
        http = FakeHTTP(
            [
                Response(
                    400,
                    {
                        "title": "Validation failed",
                        "code": "VALIDATION_FAILED",
                        "errors": [
                            {
                                "path": "locale",
                                "message": 'Invalid option: expected one of "en"|"de"|"es"',
                            }
                        ],
                    },
                )
            ]
        )
        client = api.Client(urlopen=http, sleep=lambda _seconds: None)
        with self.assertRaises(api.CwvError) as raised:
            api.currency(client, "berlin")
        self.assertIn("VALIDATION_FAILED", str(raised.exception))
        self.assertIn("locale", str(raised.exception))
        self.assertEqual(len(http.urls), 1)

    def test_network_failure(self):
        http = FakeHTTP([urllib.error.URLError("timed out")])
        client = api.Client(urlopen=http, sleep=lambda _seconds: None)
        with self.assertRaises(api.CwvError) as raised:
            api.currency(client, "berlin")
        self.assertIn("network error", str(raised.exception))
        self.assertIn("timed out", str(raised.exception))

    def test_retry_wait_is_capped(self):
        class Headers(dict):
            pass

        self.assertEqual(api.retry_wait({"Retry-After": "30"}), 10.0)
        self.assertEqual(api.retry_wait({"RateLimit-Reset": "4"}), 4.0)
        self.assertEqual(api.retry_wait({}), 2.0)


class PackageTest(unittest.TestCase):
    def test_xcu_matches_the_function_table(self):
        text = (ROOT / "CalcAddIns.xcu").read_text(encoding="utf-8")
        self.assertEqual(text, api.render_xcu())
        for name, spec in api.FUNCTIONS:
            self.assertIn('oor:name="' + name + '"', text)
            for param, _description in spec["params"]:
                self.assertNotIn("_", param)
                self.assertIn('oor:name="' + param + '"', text)

    def test_idl_matches_the_function_table(self):
        text = (ROOT / "idl" / "XCoworkingView.idl").read_text(encoding="utf-8")
        for name, spec in api.FUNCTIONS:
            self.assertIn(name + "(", text)
            if spec["params"]:
                self.assertIn(spec["params"][0][0], text)
        self.assertIn("com::sun::star::sheet::XAddIn", text)
        self.assertNotIn("CWV_SPACES([in] string", text)

    def test_description_xml_identity_publisher_and_license(self):
        text = (ROOT / "description.xml").read_text(encoding="utf-8")
        self.assertIn('value="com.coworkingview.calc"', text)
        self.assertIn('value="0.1.0"', text)
        self.assertEqual(api.VERSION, "0.1.0")
        self.assertIn('value="all"', text)
        self.assertIn('lo:LibreOffice-minimal-version value="7.0"', text)
        self.assertIn('xlink:href="https://coworkingview.com"', text)
        self.assertIn(">CoworkingView</name>", text)
        self.assertNotIn("www.coworkingview.com", text)
        self.assertIn("registration/license.txt", text)
        self.assertIn("pkg-description/pkg-description.en", text)
        self.assertIn("icons/icon.png", text)
        self.assertIn("icons/icon_hc.png", text)
        license_text = (ROOT / "registration" / "license.txt").read_text(encoding="utf-8")
        self.assertIn("MIT License", license_text)
        self.assertGreater(len(license_text.strip()), 80)
        description = (ROOT / "pkg-description" / "pkg-description.en").read_text(
            encoding="utf-8"
        )
        self.assertIn("Homepage: https://coworkingview.com", description)

    def test_icons_are_png_and_not_a_flat_red_square(self):
        for name in ("icon.png", "icon_hc.png", "coworkingview-mark.png"):
            raw = (ROOT / "icons" / name).read_bytes()
            self.assertTrue(raw.startswith(b"\x89PNG\r\n\x1a\n"), name)
            self.assertGreater(len(raw), 200, name)
        # A flat red placeholder is a few dozen bytes of one colour.
        self.assertGreater((ROOT / "icons" / "icon.png").stat().st_size, 500)


if __name__ == "__main__":
    unittest.main()
