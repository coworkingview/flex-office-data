"""HTTP mocks so the suite never calls the CoworkingView API."""

from __future__ import annotations

import copy
from collections.abc import Callable
from typing import Any

import pytest
import requests_mock

from tests.support import dump_json, load_json

Handler = Callable[..., str]


def default_properties(request: Any, context: Any) -> str:
    """One page of the Berlin catalogue fixture.

    The fixture's own ``pageCount`` is for a page of three cards. Report a
    single page so the standard sync does not walk the same cards again.
    """
    payload = copy.deepcopy(load_json("properties_berlin.json"))
    page = int(request.qs.get("page", ["1"])[0])
    payload["meta"]["pagination"]["page"] = page
    payload["meta"]["pagination"]["pageCount"] = 1
    if page > 1:
        payload["data"] = []
    return dump_json(context, payload)


def default_rates(request: Any, context: Any) -> str:
    """Price Index fixture. The query string is ignored by the fixture."""
    del request
    return dump_json(context, load_json("market_rates.json"))


@pytest.fixture(autouse=True)
def api():
    """Mock both endpoints. Tests replace ``api["properties"]`` or ``api["rates"]``."""
    state: dict[str, Handler] = {
        "properties": default_properties,
        "rates": default_rates,
    }
    with requests_mock.Mocker() as mocker:
        mocker.get(
            requests_mock.ANY,
            additional_matcher=lambda request: "/v1/properties" in request.path,
            text=lambda request, context: state["properties"](request, context),
        )
        mocker.get(
            requests_mock.ANY,
            additional_matcher=lambda request: request.path.endswith("/v1/market/rates"),
            text=lambda request, context: state["rates"](request, context),
        )
        state["mocker"] = mocker  # type: ignore[assignment]
        yield state
