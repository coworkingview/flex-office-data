"""Headless matplotlib, and paths to the shared fixtures."""

from __future__ import annotations

import json
from pathlib import Path

import matplotlib

matplotlib.use("Agg")

REPO = Path(__file__).resolve().parents[3]
FIXTURES = REPO / "spec" / "fixtures"
GOLDEN = REPO / "spec" / "golden"


def load_fixture(name: str) -> dict:
    return json.loads((FIXTURES / name).read_text(encoding="utf-8"))
