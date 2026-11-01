"""Shared fixture paths and JSON response helpers."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[4]
FIXTURES = REPO_ROOT / "spec" / "fixtures"
GOLDEN = REPO_ROOT / "spec" / "golden"


def load_json(name: str) -> dict[str, Any]:
    """Read one shared API fixture from the monorepo."""
    path = FIXTURES / name
    if not path.is_file():
        raise FileNotFoundError(
            f"Missing {path}. Run pytest from the flex-office-data checkout."
        )
    return json.loads(path.read_text(encoding="utf-8"))


def dump_json(
    context: Any,
    payload: Any,
    status: int = 200,
    headers: dict[str, str] | None = None,
) -> str:
    """Body for a requests-mock response."""
    context.status_code = status
    context.headers["Content-Type"] = "application/json"
    if headers:
        context.headers.update(headers)
    return json.dumps(payload)
