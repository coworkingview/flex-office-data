"""Write ``docs/example.png`` from ``spec/fixtures/market_rates.json``.

The opener returns that recorded response and refuses any other path. No
request leaves the process.

    python tools/render_example.py
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import matplotlib

matplotlib.use("Agg", force=True)

import matplotlib.pyplot as plt

SRC = Path(__file__).resolve().parents[1] / "src"
if str(SRC) not in sys.path:
    sys.path.insert(0, str(SRC))

from mpl_coworkingview import plot_city_rates, plot_rate_comparison  # noqa: E402
from mpl_coworkingview._http import Client  # noqa: E402

REPO = Path(__file__).resolve().parents[3]
FIXTURE = REPO / "spec" / "fixtures" / "market_rates.json"
DEFAULT_OUTPUT = Path(__file__).resolve().parents[1] / "docs" / "example.png"


class _Response:
    def __init__(self, body: bytes) -> None:
        self.status = 200
        self.reason = "OK"
        self.headers: dict[str, str] = {}
        self._body = body

    def read(self) -> bytes:
        return self._body

    def __enter__(self) -> _Response:
        return self

    def __exit__(self, *args: object) -> bool:
        return False


class FixtureOpener:
    """Serves the recorded Price Index fixture."""

    def __init__(self, body: bytes) -> None:
        self.body = body
        self.urls: list[str] = []

    def open(self, request, timeout=None):  # type: ignore[no-untyped-def]
        url = request.full_url
        self.urls.append(url)
        if url.startswith("https://fixture.invalid/v1/market/rates?"):
            return _Response(self.body)
        raise AssertionError(f"refusing unexpected URL {url}")


def render(path: Path) -> None:
    """Draw Berlin's monthly rates and a Berlin/Madrid flex-desk comparison."""
    payload = json.loads(FIXTURE.read_text(encoding="utf-8"))
    opener = FixtureOpener(json.dumps(payload).encode("utf-8"))
    client = Client(base_url="https://fixture.invalid", opener=opener)
    fig, axes = plt.subplots(1, 2, figsize=(9.8, 4.6), layout="constrained")
    plot_city_rates(axes[0], "berlin", client=client)
    plot_rate_comparison(axes[1], ["berlin", "madrid"], product="flex_desk", client=client)
    fig.savefig(path, dpi=140, bbox_inches="tight", facecolor="white")
    plt.close(fig)
    if opener.urls[0] != ("https://fixture.invalid/v1/market/rates?locale=en&city=berlin"):
        raise AssertionError(opener.urls[0])
    if opener.urls[1] != "https://fixture.invalid/v1/market/rates?locale=en":
        raise AssertionError(opener.urls[1])


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    render(args.output)
    print(args.output)


if __name__ == "__main__":
    main()
