"""The scripts in examples/ run against the fake API (they must not rot)."""

from __future__ import annotations

import runpy
from pathlib import Path
from typing import Any, Callable

import pytest

import coworkingview

from .conftest import FakeAPI, Reply

EXAMPLES = Path(__file__).resolve().parent.parent / "examples"
Loader = Callable[[str], Any]


@pytest.fixture
def use_fake(monkeypatch: pytest.MonkeyPatch, api: FakeAPI) -> FakeAPI:
    if not EXAMPLES.is_dir():
        pytest.skip("examples/ not available")
    monkeypatch.setattr(coworkingview, "_default", api.client())
    return api


def run(name: str, *args: str) -> None:
    namespace = runpy.run_path(str(EXAMPLES / name))
    namespace["main"](*args)


def test_compare_private_offices(
    use_fake: FakeAPI, load_fixture: Loader, capsys: pytest.CaptureFixture[str]
) -> None:
    use_fake.queue(Reply(body=load_fixture("market_rates.json")))
    run("compare_private_offices.py", "EUR")
    out = capsys.readouterr().out
    assert out.index("Abu Dhabi") < out.index("Berlin") < out.index("Madrid")  # by median
    assert "CC BY 4.0" in out
    assert use_fake.requests[0].query["currency"] == "EUR"


def test_compare_private_offices_empty(
    use_fake: FakeAPI, capsys: pytest.CaptureFixture[str]
) -> None:
    use_fake.queue(Reply(body={"data": {"cities": []}}))
    run("compare_private_offices.py")
    assert "No private-office figures" in capsys.readouterr().out


def test_meeting_and_event_spaces(
    use_fake: FakeAPI, load_fixture: Loader, capsys: pytest.CaptureFixture[str]
) -> None:
    first = load_fixture("properties_berlin.json")
    first["meta"]["pagination"]["pageCount"] = 1
    use_fake.queue(
        Reply(body=first),
        Reply(body=load_fixture("properties_empty.json")),
    )
    run("meeting_and_event_spaces.py", "berlin")
    out = capsys.readouterr().out
    assert "Meeting rooms in berlin: showing 3 of 110" in out
    assert "Event spaces in berlin: showing 0 of 0" in out
    assert "https://coworkingview.com/en/workspace/regus-charlottenburg-berlin" in out
    products = [r.query["pricingOptionType"] for r in use_fake.requests]
    assert products == ["meeting_room", "event_space"]
