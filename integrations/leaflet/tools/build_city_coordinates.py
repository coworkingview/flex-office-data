#!/usr/bin/env python3
"""Build the city centroid table from GeoNames.

Reads ``GET /v1/market/rates`` (or a saved response) and the GeoNames country
dumps. A slug is written only when one populated place in that country matches
the city name, its ASCII name, or an alternate name. Ambiguous names are
omitted. Coordinates are copied from the dump; this script does not invent any.

GeoNames is licensed under CC BY 4.0:
https://creativecommons.org/licenses/by/4.0/
https://www.geonames.org/
"""

from __future__ import annotations

import argparse
import json
import math
import re
import sys
import unicodedata
import urllib.request
import zipfile
from pathlib import Path

SKIP_CODES = {"PPLH", "PPLQ", "PPLW", "PPLF", "PPLX"}
FEATURE_RANK = {
    "PPLC": 100,
    "PPLA": 80,
    "PPLA2": 60,
    "PPLA3": 40,
    "PPLA4": 30,
    "PPL": 20,
    "PPLG": 15,
    "PPLS": 12,
    "PPLL": 8,
}
DUMP_URL = "https://download.geonames.org/export/dump/{cc}.zip"
RATES_URL = "https://api.coworkingview.com/v1/market/rates?locale=en"
USER_AGENT = (
    "leaflet-coworkingview/0.1.0 "
    "(+https://github.com/coworkingview/flex-office-data)"
)


def norm(value: str) -> str:
    text = unicodedata.normalize("NFKD", value.strip())
    text = "".join(ch for ch in text if not unicodedata.combining(ch))
    text = text.lower().replace("ß", "ss")
    text = re.sub(r"[^a-z0-9]+", " ", text)
    return re.sub(r"\s+", " ", text).strip()


def haversine_km(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    radius = 6371.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlng = math.radians(lng2 - lng1)
    hav = math.sin(dphi / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dlng / 2) ** 2
    return 2 * radius * math.asin(min(1.0, math.sqrt(hav)))


def load_rates(path: Path | None) -> dict:
    if path is not None:
        return json.loads(path.read_text(encoding="utf-8"))
    request = urllib.request.Request(
        RATES_URL,
        headers={"Accept": "application/json", "User-Agent": USER_AGENT},
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.loads(response.read().decode("utf-8"))


def load_places(dumps: Path, countries: set[str]) -> dict[str, list[dict]]:
    by_country: dict[str, list[dict]] = {code: [] for code in countries}
    for code in sorted(countries):
        text_path = dumps / f"{code}.txt"
        if not text_path.exists():
            archive = dumps / f"{code}.zip"
            if not archive.exists():
                request = urllib.request.Request(
                    DUMP_URL.format(cc=code),
                    headers={"User-Agent": USER_AGENT},
                )
                with urllib.request.urlopen(request, timeout=60) as response:
                    archive.write_bytes(response.read())
            with zipfile.ZipFile(archive) as zipped:
                text_path.write_bytes(zipped.read(f"{code}.txt"))
        with text_path.open(encoding="utf-8") as handle:
            for line in handle:
                parts = line.rstrip("\n").split("\t")
                if len(parts) < 19 or parts[6] != "P" or parts[7] in SKIP_CODES:
                    continue
                lat_s, lng_s = parts[4], parts[5]
                if not re.fullmatch(r"-?\d+(?:\.\d+)?", lat_s):
                    continue
                if not re.fullmatch(r"-?\d+(?:\.\d+)?", lng_s):
                    continue
                lat, lng = float(lat_s), float(lng_s)
                if not (-90 <= lat <= 90 and -180 <= lng <= 180):
                    continue
                try:
                    population = int(parts[14] or 0)
                except ValueError:
                    population = 0
                alternates = [item for item in parts[3].split(",") if item]
                by_country.setdefault(code, []).append(
                    {
                        "id": int(parts[0]),
                        "name": parts[1],
                        "lat": lat_s,
                        "lng": lng_s,
                        "lat_f": lat,
                        "lng_f": lng,
                        "code": parts[7],
                        "pop": population,
                        "nname": norm(parts[1]),
                        "nascii": norm(parts[2]),
                        "nalts": {norm(item) for item in alternates if norm(item)},
                    }
                )
    return by_country


def lookup(places: list[dict], query: str) -> list[tuple[int, dict]]:
    found: list[tuple[int, dict]] = []
    if not query:
        return found
    for place in places:
        if query == place["nname"] or query == place["nascii"]:
            found.append((3, place))
        elif query in place["nalts"]:
            found.append((2, place))
    return found


def dedupe(candidates: list[tuple[int, dict]]) -> list[dict]:
    best: dict[int, dict] = {}
    for level, place in candidates:
        current = best.get(place["id"])
        if current is None or level > current["level"]:
            best[place["id"]] = {**place, "level": level}
    kept: list[dict] = []
    for place in best.values():
        if any(
            haversine_km(place["lat_f"], place["lng_f"], other["lat_f"], other["lng_f"]) < 2
            and place["level"] <= other["level"]
            and place["pop"] <= other["pop"]
            and place["id"] != other["id"]
            for other in kept
        ):
            continue
        kept.append(place)
    return kept


def dominant(group: list[dict]) -> tuple[dict | None, str]:
    ordered = sorted(
        group,
        key=lambda place: (
            place["pop"],
            FEATURE_RANK.get(place["code"], 0),
            -place["id"],
        ),
        reverse=True,
    )
    if len(ordered) == 1:
        return ordered[0], "unique"
    first, second = ordered[0], ordered[1]
    if first["pop"] >= 5000 and first["pop"] >= max(second["pop"], 1) * 3:
        return first, "population"
    distance = haversine_km(first["lat_f"], first["lng_f"], second["lat_f"], second["lng_f"])
    if distance < 5 and first["pop"] > 0 and second["pop"] > 0:
        return first, "nearby"
    return None, "ambiguous"


def choose(candidates: list[tuple[int, dict]]) -> tuple[dict | None, str]:
    rows = dedupe(candidates)
    if not rows:
        return None, "unmatched"
    if any(place["pop"] >= 1000 for place in rows):
        rows = [place for place in rows if place["pop"] > 0]
    if not rows:
        return None, "unmatched"
    rows.sort(key=lambda place: (place["level"], place["pop"]), reverse=True)
    top_level = rows[0]["level"]
    top = [place for place in rows if place["level"] == top_level]
    lower = [place for place in rows if place["level"] < top_level]
    picked, reason = dominant(top)
    if picked is None:
        return None, "ambiguous"
    if picked["pop"] < 1000:
        majors = [
            place
            for place in lower
            if place["pop"] >= 20000
            and haversine_km(place["lat_f"], place["lng_f"], picked["lat_f"], picked["lng_f"]) > 20
        ]
        if majors:
            major, major_reason = dominant(majors)
            if major is None:
                return None, "ambiguous"
            return major, "major-over-hamlet" if major_reason == "unique" else major_reason
    return picked, reason


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rates", type=Path, help="Saved rates JSON. Defaults to a live request.")
    parser.add_argument(
        "--dumps",
        type=Path,
        default=Path("/tmp/geonames"),
        help="Directory of GeoNames CC.txt country files.",
    )
    parser.add_argument(
        "--out",
        type=Path,
        default=Path(__file__).resolve().parents[1] / "src" / "city-coordinates.json",
    )
    args = parser.parse_args()

    payload = load_rates(args.rates)
    data = payload.get("data")
    if not isinstance(data, dict) or not isinstance(data.get("cities"), list):
        print("rates response has no data.cities array", file=sys.stderr)
        return 1
    cities = data["cities"]
    countries = {
        city.get("countryCode")
        for city in cities
        if isinstance(city, dict) and isinstance(city.get("countryCode"), str)
    }
    places = load_places(args.dumps, countries)

    matched: dict[str, dict] = {}
    omitted: list[dict] = []
    for city in cities:
        if not isinstance(city, dict):
            continue
        ref = city.get("city") if isinstance(city.get("city"), dict) else {}
        slug = ref.get("slug") if isinstance(ref.get("slug"), str) else ""
        name = ref.get("name") if isinstance(ref.get("name"), str) else ""
        country = city.get("countryCode") if isinstance(city.get("countryCode"), str) else ""
        slug = slug.strip()
        if not slug or not country:
            omitted.append({"slug": slug, "name": name, "reason": "missing-slug-or-country"})
            continue
        queries: list[str] = []
        for raw in (name, slug.replace("-", " ")):
            query = norm(raw)
            if query and query not in queries:
                queries.append(query)
        found: list[tuple[int, dict]] = []
        for query in queries:
            found.extend(lookup(places.get(country, []), query))
        place, reason = choose(found)
        if place is None:
            omitted.append({"slug": slug, "name": name, "countryCode": country, "reason": reason})
            continue
        matched[slug] = {
            "lat": place["lat"],
            "lng": place["lng"],
            "geonameId": place["id"],
            "name": place["name"],
            "countryCode": country,
            "featureCode": place["code"],
            "_reason": reason,
            "_pop": place["pop"],
            "_level": place["level"],
        }

    # Emit lat/lng as the dump's own decimal tokens, not a re-rounded float.
    cities_out: dict[str, dict] = {}
    audit = []
    for slug in sorted(matched):
        row = matched[slug]
        cities_out[slug] = {
            "lat": row["lat"],
            "lng": row["lng"],
            "geonameId": row["geonameId"],
            "name": row["name"],
            "countryCode": row["countryCode"],
            "featureCode": row["featureCode"],
        }
        audit.append(
            f"{slug}\t{row['name']}\t{row['featureCode']}\tpop={row['_pop']}\t"
            f"L{row['_level']}\t{row['_reason']}\t{row['geonameId']}\t{row['lat']},{row['lng']}"
        )

    document = {
        "source": {
            "name": "GeoNames",
            "url": "https://www.geonames.org/",
            "dump": "https://download.geonames.org/export/dump/",
            "license": "CC BY 4.0",
            "licenseUrl": "https://creativecommons.org/licenses/by/4.0/",
            "retrieved": "2026-11-03",
            "ratesRetrieved": "2026-11-03",
            "ratesUrl": "https://api.coworkingview.com/v1/market/rates?locale=en",
            "note": (
                "One centroid per city slug returned by that rates response, and only when a "
                "single GeoNames populated place in the same country matched the city name, "
                "its ASCII name, or an alternate name. Ambiguous slugs are listed in omitted "
                "and are not given coordinates."
            ),
        },
        "omitted": omitted,
        "cities": cities_out,
    }
    args.out.parent.mkdir(parents=True, exist_ok=True)
    # lat/lng stay the dump's decimal tokens. They are strings until this
    # substitution so json does not re-round them.
    encoded = json.dumps(document, ensure_ascii=False, indent=2)
    encoded = re.sub(
        r'"(lat|lng)": "(-?\d+(?:\.\d+)?)"',
        lambda match: f'"{match.group(1)}": {match.group(2)}',
        encoded,
    )
    args.out.write_text(encoded + "\n", encoding="utf-8")
    print(f"matched {len(cities_out)} omitted {len(omitted)} -> {args.out}")
    print("-- omitted --")
    for row in omitted:
        print(f"{row.get('slug')}\t{row.get('name')}\t{row.get('reason')}")
    print("-- audit --")
    print("\n".join(audit))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
