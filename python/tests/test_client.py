"""Endpoint logic: query building, pagination, validation, Space, module functions."""

from __future__ import annotations

import dataclasses
import subprocess
import sys
from typing import Any, Callable

import pandas as pd
import pytest

import coworkingview
from coworkingview import Client, Space

from .conftest import FakeAPI, Reply, Seen

Loader = Callable[[str], Any]


def card(i: int) -> dict[str, Any]:
    return {"slug": f"space-{i}", "title": f"Space {i}", "city": {"slug": "berlin"}}


def paged(total: int, seed: int = 42) -> Callable[[Seen], Reply]:
    """Responder that serves ``total`` cards in pages, like the real API."""

    def respond(seen: Seen) -> Reply:
        page, size = int(seen.query["page"]), int(seen.query["pageSize"])
        start = (page - 1) * size
        cards = [card(i) for i in range(start, min(start + size, total))]
        page_count = -(-total // size)
        meta = {
            "pagination": {"page": page, "pageSize": size, "total": total, "pageCount": page_count},
            "seed": seed + page,  # a different seed per page: the client must keep page 1's
            "citation": {"text": f"citation page {page}"},
            "catalogueNotice": "notice",
        }
        return Reply(body={"data": cards, "meta": meta})

    return respond


def test_rates_query_parameters(api: FakeAPI) -> None:
    api.queue(Reply(body={"data": {"cities": []}}))
    api.client().rates(city="berlin", country="DE", currency="eur", locale="de")
    seen = api.requests[0]
    assert seen.path == "/v1/market/rates"
    assert seen.query == {"locale": "de", "city": "berlin", "country": "DE", "currency": "EUR"}


def test_spaces_query_parameters(api: FakeAPI) -> None:
    api.responder = paged(1)
    api.client().spaces(
        city="berlin",
        country="DE",
        zone="mitte",
        operator="regus",
        product="meeting_room",
        min_capacity=8,
        min_price=10,
        max_price=99.5,
        currency="EUR",
        sort="price-asc",
        limit=10,
        locale="es",
    )
    assert api.requests[0].path == "/v1/properties"
    assert api.requests[0].query == {
        "locale": "es",
        "city": "berlin",
        "country": "DE",
        "zone": "mitte",
        "operator": "regus",
        "pricingOptionType": "meeting_room",
        "minCapacity": "8",
        "minPrice": "10",
        "maxPrice": "99.5",
        "currency": "EUR",
        "sortBy": "price-asc",
        "pageSize": "10",
        "page": "1",
    }


def test_spaces_paginates_and_reuses_seed(api: FakeAPI) -> None:
    api.responder = paged(500)
    df = api.client().spaces(limit=120)
    assert len(df) == 120
    assert df["slug"].tolist() == [f"space-{i}" for i in range(120)]
    assert [r.query["page"] for r in api.requests] == ["1", "2", "3"]
    assert all(r.query["pageSize"] == "50" for r in api.requests)
    assert "seed" not in api.requests[0].query
    assert [r.query["seed"] for r in api.requests[1:]] == ["43", "43"]
    assert df.attrs == {"attribution": "citation page 1", "notice": "notice", "total": 500}


def test_spaces_no_seed_unless_random(api: FakeAPI) -> None:
    api.responder = paged(80)
    df = api.client().spaces(sort="date-desc", limit=200)
    assert len(df) == 80
    assert len(api.requests) == 2
    assert "seed" not in api.requests[1].query


def test_spaces_stops_at_page_count(api: FakeAPI) -> None:
    api.responder = paged(30)
    df = api.client().spaces(limit=200)
    assert len(df) == 30
    assert len(api.requests) == 1


def test_spaces_small_limit_is_one_small_page(api: FakeAPI) -> None:
    api.responder = paged(500)
    df = api.client().spaces(limit=5)
    assert len(df) == 5
    assert len(api.requests) == 1
    assert api.requests[0].query["pageSize"] == "5"


def test_spaces_never_exceeds_200(api: FakeAPI) -> None:
    api.responder = paged(10_000)
    df = api.client().spaces(limit=200)
    assert len(df) == 200
    assert len(api.requests) == 4


def test_spaces_stops_without_pagination(api: FakeAPI) -> None:
    api.queue(Reply(body={"data": [card(1)], "meta": {}}))
    df = api.client().spaces()
    assert len(df) == 1
    assert df.attrs == {"attribution": None, "notice": None, "total": None}


def test_spaces_urls_follow_locale(api: FakeAPI) -> None:
    api.responder = paged(1)
    client = api.client()
    urls = [client.spaces(locale=loc, limit=1)["url"].item() for loc in ("en", "es", "de")]
    assert urls == [
        "https://coworkingview.com/en/workspace/space-0",
        "https://coworkingview.com/es/oficina/space-0",
        "https://coworkingview.com/de/buero/space-0",
    ]


def test_spaces_minimal_card_gives_nulls(api: FakeAPI) -> None:
    api.queue(Reply(body={"data": [{"slug": "a", "title": "A"}], "meta": {}}))
    row = api.client().spaces().iloc[0]
    for col in ("city_slug", "zone_slug", "operator_name", "lat", "featured", "market_verdict"):
        assert pd.isna(row[col]), col
    assert pd.isna(row["updated_at"])


@pytest.mark.parametrize("limit", [201, 1000])
def test_limit_cap_explains_why(limit: int) -> None:
    with pytest.raises(ValueError, match=r"maximum of 200.*not bulk-copied"):
        Client(base_url="http://never.invalid").spaces(limit=limit)


@pytest.mark.parametrize(
    ("kwargs", "message"),
    [
        ({"locale": "fr"}, r"locale='fr' is not supported; use one of 'en', 'es', 'de'"),
        ({"currency": "JPY"}, r"currency='JPY' .* 'EUR', 'GBP', 'USD', 'CHF', 'AED', 'VES'"),
        ({"currency": 5}, r"currency=5 is not supported"),
        ({"product": "desk"}, r"product='desk' .*'flex_desk'.*'membership'"),
        ({"sort": "price"}, r"sort='price' .*'random', 'price-asc', 'date-desc', 'date-asc'"),
        ({"limit": 0}, r"limit must be a positive integer"),
        ({"limit": True}, r"limit must be a positive integer"),
        ({"limit": 1.5}, r"limit must be a positive integer"),
        ({"min_capacity": -1}, r"min_capacity must be a non-negative integer"),
        ({"min_price": "cheap"}, r"min_price must be a non-negative number"),
        ({"min_price": 100, "max_price": 50}, r"min_price \(100\) is greater than max_price"),
        ({"city": ""}, r"city must be a non-empty string"),
        ({"operator": 3}, r"operator must be a non-empty string"),
    ],
)
def test_spaces_validation(kwargs: dict[str, Any], message: str) -> None:
    with pytest.raises(ValueError, match=message):
        Client(base_url="http://never.invalid").spaces(**kwargs)


@pytest.mark.parametrize("kwargs", [{"locale": "EN"}, {"currency": "BTC"}, {"country": "  "}])
def test_rates_validation(kwargs: dict[str, Any]) -> None:
    client = Client(base_url="http://never.invalid")
    with pytest.raises(ValueError, match=r"must be|not supported"):
        client.rates(**kwargs)
    with pytest.raises(ValueError, match=r"must be|not supported"):
        client.cities(**kwargs)


def test_ves_is_passed_through(api: FakeAPI) -> None:
    api.queue(Reply(body={"data": {"cities": []}}))
    api.client().rates(currency="VES")
    assert api.requests[0].query["currency"] == "VES"


def test_space_fields(api: FakeAPI, load_fixture: Loader) -> None:
    payload = load_fixture("property_detail.json")
    api.queue(Reply(body=payload))
    s = api.client().space("sankt-oberholz-rosenthaler-berlin", locale="en")
    assert api.requests[0].path == "/v1/properties/sankt-oberholz-rosenthaler-berlin"
    assert api.requests[0].query == {"locale": "en"}
    assert isinstance(s, Space)
    assert s.slug == "sankt-oberholz-rosenthaler-berlin"
    assert s.zone_slug == "mitte"
    assert s.operator_name == "St. Oberholz"
    assert s.lat == pytest.approx(52.5294539)
    assert s.featured is True
    assert s.market_verdict == "around"
    assert s.market_median == 214.0
    assert s.market_sample_size == 72
    assert s.url == payload["data"]["webUrl"]
    assert s.updated_at == pd.Timestamp("2026-10-19T16:27:57.522Z")
    assert s.updated_at is not None
    assert str(s.updated_at.tz) == "UTC"
    assert s.address == "Rosenthaler Straße 72a, 10119 Berlin, Germany"
    assert s.capacity is None
    assert s.amenities[:2] == ("reception", "wifi")
    assert s.attribution == payload["meta"]["citation"]["text"]
    assert s.notice == payload["meta"]["catalogueNotice"]
    assert s.pricing.attrs["attribution"] == s.attribution
    assert len(s.pricing) == 5
    # Operators' prose and images never come through.
    names = {f.name for f in dataclasses.fields(Space)}
    assert not names & {"description", "images", "excerpt", "logo"}


def test_space_is_frozen_hashable_and_readable(api: FakeAPI) -> None:
    detail = {
        "slug": "a.b_c",
        "title": "A",
        "capacity": 30,
        "coordinates": {"lat": 1, "lng": 2},
        "marketPosition": None,
    }
    api.queue(Reply(body={"data": detail, "meta": {}}), Reply(body={"data": detail, "meta": {}}))
    client = api.client()
    first, second = client.space("a.b_c", locale="de"), client.space("a.b_c", locale="de")
    assert api.requests[0].path == "/v1/properties/a.b_c"
    assert first == second
    assert hash(first) == hash(second)
    assert first.capacity == 30
    assert (first.lat, first.lng) == (1.0, 2.0)
    assert first.url == "https://coworkingview.com/de/buero/a.b_c"
    assert first.attribution is None
    assert first.pricing.empty
    assert next(iter(first.pricing.columns)) == "product"
    assert "pricing" not in repr(first)
    with pytest.raises(dataclasses.FrozenInstanceError):
        first.title = "B"  # type: ignore[misc]


@pytest.mark.parametrize(
    "slug", ["", "   ", None, "a/b", "../etc", "-leading", " padded ", "x?y=1", "caf\u00e9", 5]
)
def test_space_rejects_invalid_slug(slug: Any) -> None:
    with pytest.raises(ValueError, match="slug"):
        Client(base_url="http://never.invalid").space(slug)


def test_module_functions_use_default_client(
    monkeypatch: pytest.MonkeyPatch, api: FakeAPI, load_fixture: Loader
) -> None:
    monkeypatch.setattr(coworkingview, "_default", None)
    monkeypatch.setenv("COWORKINGVIEW_API_URL", api.url)
    rates = load_fixture("market_rates.json")
    api.queue(
        Reply(body=rates),
        Reply(body=rates),
        Reply(body=load_fixture("properties_berlin.json")),
        Reply(body=load_fixture("property_detail.json")),
    )
    assert len(coworkingview.rates(city="berlin")) == 13
    assert coworkingview._default is not None
    default = coworkingview._default
    assert len(coworkingview.cities()) == 4
    assert coworkingview._default is default
    assert len(coworkingview.spaces(city="berlin", limit=3)) == 3
    assert coworkingview.space("sankt-oberholz-rosenthaler-berlin").title.startswith("St.")
    assert len(api.requests) == 4


def test_no_network_at_import() -> None:
    code = (
        "import socket\n"
        "def boom(*a, **k): raise AssertionError('network at import')\n"
        "socket.socket.connect = boom\n"
        "socket.create_connection = boom\n"
        "import coworkingview\n"
        "assert coworkingview._default is None\n"
        "print(coworkingview.__version__)\n"
    )
    out = subprocess.run([sys.executable, "-c", code], capture_output=True, text=True, check=True)
    assert out.stdout.strip() == coworkingview.__version__


def test_public_api() -> None:
    assert set(coworkingview.__all__) == {
        "APIError",
        "Client",
        "CoworkingViewError",
        "Space",
        "__version__",
        "cities",
        "rates",
        "space",
        "spaces",
    }
    for name in coworkingview.__all__:
        obj = getattr(coworkingview, name)
        if callable(obj):
            assert obj.__doc__, name
