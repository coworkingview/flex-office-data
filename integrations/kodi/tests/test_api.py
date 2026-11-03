"""Parser and HTTP behaviour for the Kodi Price Index client. No Kodi runtime."""

import json
import pathlib
import sys
import unittest
import urllib.error

ROOT = pathlib.Path(__file__).resolve().parents[1]
LIB = ROOT / "script.coworkingview" / "resources" / "lib"
FIXTURES = ROOT.parents[1] / "spec" / "fixtures"
GOLDEN = ROOT.parents[1] / "spec" / "golden" / "rates.csv"
sys.path.insert(0, str(LIB))

import api  # noqa: E402


def _load(name):
    return json.loads((FIXTURES / name).read_text(encoding="utf-8"))


class ParseIndexTest(unittest.TestCase):
    def test_matches_golden_rates(self):
        document = api.parse_index(_load("market_rates.json"))
        slugs = [city["slug"] for city in document["cities"]]
        names = [city["name"].casefold() for city in document["cities"]]
        self.assertNotIn("example-town", slugs)
        self.assertEqual(names, sorted(names))
        self.assertTrue(document["attribution"].startswith("Source: CoworkingView Price Index"))
        self.assertEqual(document["license"], "https://creativecommons.org/licenses/by/4.0/")

        golden_rows = []
        text = GOLDEN.read_text(encoding="utf-8").splitlines()
        header = text[0].split(",")
        for line in text[1:]:
            values = line.split(",")
            row = dict(zip(header, values))
            golden_rows.append(row)

        self.assertEqual(len(document["rows"]), len(golden_rows))
        for got, expected in zip(document["rows"], golden_rows):
            self.assertEqual(got["city_slug"], expected["city_slug"])
            self.assertEqual(got["city_name"], expected["city_name"])
            self.assertEqual(got["country_code"], expected["country_code"] or None)
            self.assertEqual(got["currency"], expected["currency"])
            self.assertEqual(got["product"], expected["product"])
            self.assertEqual(got["unit"], expected["unit"] or None)
            self.assertEqual(got["median"], _number(expected["median"]))
            self.assertEqual(got["p25"], _number(expected["p25"]))
            self.assertEqual(got["p75"], _number(expected["p75"]))
            self.assertEqual(got["sample_size"], int(expected["sample_size"]))
            self.assertEqual(got["property_count"], _number(expected["property_count"]))
            self.assertEqual(got["operator_count"], _number(expected["operator_count"]))
            self.assertEqual(got["low_confidence"], expected["low_confidence"] == "true")
            self.assertEqual(got["as_of"], expected["as_of"])

    def test_berlin_usd_uses_figures(self):
        document = api.parse_index(_load("market_rates_berlin_usd.json"))
        rows = api.rows_for_city(document, "berlin")
        by_product = {row["product"]: row for row in rows}
        self.assertEqual(by_product["flex_desk"]["median"], 233)
        self.assertEqual(by_product["flex_desk"]["currency"], "USD")
        self.assertEqual(by_product["flex_desk"]["unit"], "month")
        self.assertEqual(by_product["day_pass"]["unit"], "day")
        self.assertEqual(by_product["meeting_room"]["unit"], "hour")
        self.assertFalse(by_product["flex_desk"]["low_confidence"])
        self.assertEqual(
            [city["slug"] for city in api.cities_with_rates(document)],
            ["berlin"],
        )


class FetchIndexTest(unittest.TestCase):
    def test_url_is_the_rates_endpoint(self):
        seen = {}

        def opener(request, timeout):
            seen["url"] = request.full_url
            seen["accept"] = request.get_header("Accept")
            seen["agent"] = request.get_header("User-agent")
            seen["timeout"] = timeout
            return _Response(_load("market_rates_berlin_usd.json"))

        document = api.fetch_index("en", "USD", urlopen=opener, sleeper=lambda _seconds: None)
        self.assertEqual(
            seen["url"],
            "https://api.coworkingview.com/v1/market/rates?locale=en&currency=USD",
        )
        self.assertEqual(seen["accept"], "application/json")
        self.assertIn("script.coworkingview/1.0.0", seen["agent"])
        self.assertEqual(seen["timeout"], 20)
        self.assertEqual(api.rows_for_city(document, "berlin")[0]["city_slug"], "berlin")

    def test_retries_once_on_429(self):
        calls = {"n": 0}
        waits = []

        def opener(request, timeout):
            calls["n"] += 1
            if calls["n"] == 1:
                raise urllib.error.HTTPError(
                    request.full_url, 429, "Too Many Requests", {"Retry-After": "1"}, _Body(b"")
                )
            return _Response(_load("market_rates.json"))

        api.fetch_index("en", urlopen=opener, sleeper=waits.append)
        self.assertEqual(calls["n"], 2)
        self.assertEqual(waits, [1.0])

    def test_does_not_retry_a_validation_error(self):
        calls = {"n": 0}

        def opener(request, timeout):
            calls["n"] += 1
            raw = (FIXTURES / "error_validation.json").read_bytes()
            raise urllib.error.HTTPError(request.full_url, 400, "Bad Request", {}, _Body(raw))

        with self.assertRaises(api.ApiError) as caught:
            api.fetch_index("en", "EUR", urlopen=opener, sleeper=lambda _seconds: None)
        self.assertEqual(calls["n"], 1)
        self.assertEqual(caught.exception.status, 400)
        self.assertEqual(caught.exception.problem_code, "VALIDATION_FAILED")
        self.assertIn("VES", caught.exception.detail)


def _number(text):
    if text == "":
        return None
    if "." in text:
        return float(text)
    return int(text)


class _Body:
    def __init__(self, raw):
        self.raw = raw

    def read(self):
        return self.raw

    def close(self):
        return None


class _Response:
    def __init__(self, payload, status=200):
        self.status = status
        self.reason = "OK"
        self.headers = {}
        self._raw = json.dumps(payload).encode("utf-8")

    def read(self):
        return self._raw

    def __enter__(self):
        return self

    def __exit__(self, *_args):
        return False


if __name__ == "__main__":
    unittest.main()
