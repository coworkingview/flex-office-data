"""Price Index rows follow spec/SPEC.md section 3."""

from __future__ import annotations

import json

import pytest

from coworkingview_provider.exceptions import CoworkingViewError
from coworkingview_provider.parse import city_rates_document, rate_rows
from tests.support import berlin_rates


def test_berlin_fixture_rows_match_the_recorded_index():
    payload = berlin_rates()
    rows = rate_rows(payload["data"])
    by_product = {row["product"]: row for row in rows}

    assert [row["product"] for row in rows] == [
        "flex_desk",
        "fix_desk",
        "private_office",
        "day_pass",
        "meeting_room",
    ]
    flex = by_product["flex_desk"]
    assert flex["median"] == 233
    assert flex["p25"] == 216
    assert flex["p75"] == 317
    assert flex["unit"] == "month"
    assert flex["sample_size"] == 72
    assert flex["property_count"] == 66
    assert flex["operator_count"] == 38
    assert flex["low_confidence"] is False
    assert flex["currency"] == "USD"
    assert flex["city_slug"] == "berlin"
    assert flex["as_of"] == "2026-10-27T21:06:48.313Z"
    assert by_product["day_pass"]["unit"] == "day"
    assert by_product["day_pass"]["median"] == 38
    assert by_product["meeting_room"]["unit"] == "hour"
    assert by_product["meeting_room"]["median"] == 35


def test_document_keeps_attribution_and_drops_catalogue_names():
    document = city_rates_document(berlin_rates(), city="berlin", locale="en")
    text = json.dumps(document)
    assert document["attribution"].startswith("Source: CoworkingView Price Index")
    assert document["license"] == "https://creativecommons.org/licenses/by/4.0/"
    assert document["contract_version"] == "1.0.0"
    assert document["rates"][0]["attribution"] == document["attribution"]
    assert document["rates"][0]["license"] == document["license"]
    # buildings[] on the city object names individual spaces. Those are not
    # Price Index rows and must not ride along in the XCom.
    assert "CoWoS" not in text
    assert "MACHWERK" not in text


def test_bytype_fallback_and_low_confidence():
    payload = {
        "data": {
            "cities": [
                {
                    "city": {"slug": "madrid", "name": "Madrid"},
                    "countryCode": "ES",
                    "currency": "EUR",
                    "byType": [
                        {
                            "optionType": "flex_desk",
                            "median": {"amount": 200, "currency": "EUR"},
                            "sampleSize": 4,
                        }
                    ],
                    "eventSpace": {
                        "median": {"amount": 80, "currency": "EUR"},
                        "sampleSize": 3,
                    },
                }
            ],
            "asOf": "2026-01-01T00:00:00Z",
            "attribution": "credit",
            "licenseUrl": "https://creativecommons.org/licenses/by/4.0/",
        },
        "meta": {},
    }
    rows = rate_rows(payload["data"])
    assert [row["product"] for row in rows] == ["flex_desk", "event_space"]
    assert rows[0]["p25"] is None
    assert rows[0]["property_count"] is None
    assert rows[0]["low_confidence"] is True
    assert rows[0]["unit"] == "month"
    assert rows[1]["unit"] == "hour"
    assert rows[1]["product"] == "event_space"


def test_unpublished_city_is_named_in_the_error():
    payload = {
        "data": {
            "cities": [],
            "unpublished": [{"city": {"slug": "leipzig", "name": "Leipzig"}}],
            "asOf": "2026-01-01T00:00:00Z",
        },
        "meta": {"contractVersion": "1.0.0"},
    }
    with pytest.raises(CoworkingViewError, match="unpublished"):
        city_rates_document(payload, city="leipzig", locale="en")


def test_unknown_city_and_missing_product():
    payload = berlin_rates()
    with pytest.raises(CoworkingViewError, match="nowhere"):
        city_rates_document(payload, city="nowhere", locale="en")
    with pytest.raises(CoworkingViewError, match="Published products"):
        city_rates_document(payload, city="berlin", locale="en", product="virtual_office")


def test_malformed_city_object_is_an_error_not_a_partial_row():
    payload = {"data": {"cities": [{"city": {}}]}, "meta": {}}
    with pytest.raises(CoworkingViewError, match="expected shape"):
        city_rates_document(payload, city="berlin", locale="en")
