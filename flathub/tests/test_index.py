"""Parser, HTTP retry and on-disk cache for CoworkingView Rates."""

from __future__ import annotations

import json
import threading
import unittest
import xml.etree.ElementTree as ET
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from coworkingview_rates.index import (
    cache_file,
    fetch_market,
    format_amount,
    load_cache,
    parse_index,
    resolve_base_url,
    save_cache,
)

ROOT = Path(__file__).resolve().parents[2]
FIXTURE = ROOT / "spec" / "fixtures" / "market_rates.json"
METAINFO = ROOT / "flathub" / "com.coworkingview.Rates.metainfo.xml"
DESKTOP = ROOT / "flathub" / "com.coworkingview.Rates.desktop"

ENVELOPE = {
    "data": {
        "cities": [],
        "unpublished": [],
        "asOf": "2026-11-04T00:00:00Z",
        "attribution": "Source",
        "licenseUrl": "https://creativecommons.org/licenses/by/4.0/",
    }
}


class Handler(BaseHTTPRequestHandler):
    def do_GET(self) -> None:
        server: ProbeServer = self.server  # type: ignore[assignment]
        server.hits += 1
        mode = server.mode
        if mode == "retry" and server.hits == 1:
            body = b'{"title":"Unavailable","detail":"busy"}'
            self.send_response(503)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Retry-After", "0")
            self.end_headers()
            self.wfile.write(body)
            return
        if mode == "bad":
            body = b'{"title":"Bad request","detail":"currency is not supported","code":"VALIDATION_FAILED"}'
            self.send_response(400)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        if mode == "text":
            body = b"not-json"
            self.send_response(200)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        body = json.dumps(ENVELOPE).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt: str, *args: object) -> None:
        return


class ProbeServer(ThreadingHTTPServer):
    hits: int
    mode: str


class IndexTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        payload = json.loads(FIXTURE.read_text(encoding="utf-8"))
        cls.index = parse_index(payload["data"])

    def test_berlin_figures_match_the_fixture(self) -> None:
        berlin = next(city for city in self.index.cities if city.slug == "berlin")
        self.assertEqual(berlin.name, "Berlin")
        self.assertEqual(berlin.country_code, "DE")
        self.assertEqual(berlin.currency, "EUR")
        self.assertTrue(berlin.published)
        self.assertEqual(berlin.entry_median, 265)
        self.assertEqual(berlin.property_count, 85)
        by_product = {figure.product: figure for figure in berlin.figures}
        flex = by_product["flex_desk"]
        self.assertEqual(flex.median, 214)
        self.assertEqual(flex.p25, 199)
        self.assertEqual(flex.p75, 292)
        self.assertEqual(flex.sample_size, 72)
        self.assertEqual(flex.unit, "month")
        self.assertFalse(flex.low_confidence)
        self.assertEqual(by_product["fix_desk"].median, 310)
        self.assertEqual(by_product["private_office"].median, 480)
        self.assertEqual(by_product["day_pass"].median, 35)
        self.assertEqual(by_product["day_pass"].unit, "day")
        self.assertEqual(by_product["meeting_room"].median, 32)
        self.assertEqual(by_product["meeting_room"].unit, "hour")
        self.assertEqual(
            [figure.product for figure in berlin.figures],
            ["flex_desk", "fix_desk", "private_office", "day_pass", "meeting_room"],
        )

    def test_small_samples_are_low_confidence_and_unpublished_cities_stay(self) -> None:
        abu_dhabi = next(city for city in self.index.cities if city.slug == "abu-dhabi")
        self.assertTrue(all(figure.low_confidence for figure in abu_dhabi.figures))
        unpublished = next(city for city in self.index.cities if city.slug == "example-town")
        self.assertFalse(unpublished.published)
        self.assertEqual(unpublished.figures, ())
        published_flags = [city.published for city in self.index.cities]
        self.assertEqual(published_flags, sorted(published_flags, reverse=True))

    def test_attribution_is_kept(self) -> None:
        self.assertIn("CC BY 4.0", self.index.attribution or "")
        self.assertEqual(self.index.license_url, "https://creativecommons.org/licenses/by/4.0/")
        self.assertEqual(self.index.as_of, "2026-10-27T21:06:48.313Z")

    def test_format_amount(self) -> None:
        self.assertEqual(format_amount(214, "EUR"), "214 EUR")
        self.assertEqual(format_amount(1800, "AED"), "1,800 AED")
        self.assertEqual(format_amount(None, "EUR"), "—")

    def test_base_url_rejects_userinfo(self) -> None:
        with self.assertRaises(Exception):
            resolve_base_url("https://user:secret@api.coworkingview.com")


class HttpTests(unittest.TestCase):
    def setUp(self) -> None:
        self.server = ProbeServer(("127.0.0.1", 0), Handler)
        self.server.hits = 0
        self.server.mode = "ok"
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        host, port = self.server.server_address[:2]
        self.origin = f"http://{host}:{port}"

    def tearDown(self) -> None:
        self.server.shutdown()
        self.server.server_close()

    def test_retries_a_503_once(self) -> None:
        self.server.mode = "retry"
        data = fetch_market(base_url=self.origin, timeout=2, sleep=lambda _seconds: None)
        self.assertEqual(self.server.hits, 2)
        self.assertEqual(data["attribution"], "Source")

    def test_does_not_retry_a_400(self) -> None:
        self.server.mode = "bad"
        with self.assertRaises(Exception) as caught:
            fetch_market(base_url=self.origin, timeout=2, sleep=lambda _seconds: None)
        self.assertEqual(self.server.hits, 1)
        self.assertIn("HTTP 400", str(caught.exception))
        self.assertIn("currency is not supported", str(caught.exception))

    def test_rejects_a_non_json_body(self) -> None:
        self.server.mode = "text"
        with self.assertRaises(Exception) as caught:
            fetch_market(base_url=self.origin, timeout=2, sleep=lambda _seconds: None)
        self.assertIn("not valid JSON", str(caught.exception))


class CacheTests(unittest.TestCase):
    def test_round_trip(self) -> None:
        payload = json.loads(FIXTURE.read_text(encoding="utf-8"))
        directory = self.id().replace(".", "_")
        path = cache_file(f"/tmp/{directory}")
        save_cache(payload["data"], path, "2026-11-04T12:00:00Z")
        loaded = load_cache(path)
        self.assertIsNotNone(loaded)
        assert loaded is not None
        index, saved_at = loaded
        self.assertEqual(saved_at, "2026-11-04T12:00:00Z")
        self.assertEqual(next(city.slug for city in index.cities if city.slug == "berlin"), "berlin")

    def test_corrupt_cache_is_ignored(self) -> None:
        path = "/tmp/coworkingview-rates-corrupt/market-rates.json"
        Path(path).parent.mkdir(parents=True, exist_ok=True)
        Path(path).write_text("{", encoding="utf-8")
        self.assertIsNone(load_cache(path))


class MetadataTests(unittest.TestCase):
    def test_metainfo_follows_the_listing_rules(self) -> None:
        root = ET.parse(METAINFO).getroot()
        self.assertEqual(root.findtext("id"), "com.coworkingview.Rates")
        self.assertEqual(root.findtext("metadata_license"), "CC0-1.0")
        self.assertEqual(root.findtext("project_license"), "MIT")
        self.assertEqual(root.findtext("url[@type='homepage']"), "https://coworkingview.com")
        self.assertEqual(
            root.findtext("url[@type='bugtracker']"),
            "https://github.com/coworkingview/flex-office-data/issues",
        )
        self.assertEqual(
            root.findtext("url[@type='vcs-browser']"),
            "https://github.com/coworkingview/flex-office-data",
        )
        developer = root.find("developer")
        self.assertIsNotNone(developer)
        assert developer is not None
        self.assertEqual(developer.get("id"), "com.coworkingview")
        self.assertEqual(developer.findtext("name"), "CoworkingView")
        summary = (root.findtext("summary") or "").strip()
        self.assertFalse(summary.endswith("."))
        self.assertLessEqual(len(summary), 35)
        self.assertNotIn("app", summary.casefold().split())
        for word in ("best", "simple", "easy", "powerful", "seamless", "modern", "ultimate", "leading"):
            self.assertNotIn(word, summary.casefold())
        self.assertEqual(root.find("content_rating").get("type"), "oars-1.1")  # type: ignore[union-attr]
        image = root.find("screenshots/screenshot/image")
        self.assertIsNotNone(image)
        assert image is not None
        self.assertIn("/flatpak-v0.1.0/", image.text or "")
        self.assertTrue((image.text or "").startswith("https://raw.githubusercontent.com/"))
        caption = root.findtext("screenshots/screenshot/caption") or ""
        self.assertFalse(caption.endswith("."))
        release = root.find("releases/release")
        self.assertIsNotNone(release)
        assert release is not None
        self.assertEqual(release.get("version"), "0.1.0")
        self.assertEqual(release.get("date"), "2026-11-04")
        colors = {
            (color.get("scheme_preference"), (color.text or "").lower())
            for color in root.findall("branding/color")
        }
        self.assertIn(("light", "#c6a15a"), colors)
        self.assertIn(("dark", "#5c4314"), colors)

    def test_desktop_file_matches_the_app_id(self) -> None:
        text = DESKTOP.read_text(encoding="utf-8")
        self.assertIn("Name=CoworkingView Rates\n", text)
        self.assertIn("Comment=Browse coworking prices by city\n", text)
        self.assertIn("Exec=com.coworkingview.Rates\n", text)
        self.assertIn("Icon=com.coworkingview.Rates\n", text)
        self.assertIn("Terminal=false\n", text)
        self.assertNotIn(".", text.split("Comment=", 1)[1].split("\n", 1)[0][-1:])


if __name__ == "__main__":
    unittest.main()
