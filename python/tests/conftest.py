"""Shared fixtures: the spec directory and a local fake API server."""

from __future__ import annotations

import json
import os
import threading
from collections.abc import Iterator
from dataclasses import dataclass, field
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any, Callable, Union
from urllib.parse import parse_qs, urlsplit

import pytest

from coworkingview import Client


def _find_spec() -> Path | None:
    """Locate ``spec/``: env override, the monorepo checkout, or an unpacked sdist."""
    override = os.environ.get("COWORKINGVIEW_SPEC_DIR")
    candidates = [Path(override)] if override else []
    here = Path(__file__).resolve().parent
    candidates += [here.parent.parent / "spec", here.parent / "spec"]
    for candidate in candidates:
        if (candidate / "fixtures").is_dir() and (candidate / "golden").is_dir():
            return candidate
    return None


SPEC_DIR = _find_spec()


@pytest.fixture(scope="session")
def spec_dir() -> Path:
    if SPEC_DIR is None:
        pytest.skip("spec/ fixtures not found (set COWORKINGVIEW_SPEC_DIR)")
    return SPEC_DIR


@pytest.fixture(scope="session")
def load_fixture(spec_dir: Path) -> Callable[[str], Any]:
    def load(name: str) -> Any:
        return json.loads((spec_dir / "fixtures" / name).read_text(encoding="utf-8"))

    return load


Body = Union[bytes, str, dict[str, Any], list[Any]]


@dataclass
class Reply:
    status: int = 200
    body: Body = b"{}"
    headers: dict[str, str] = field(default_factory=dict)


@dataclass
class Seen:
    path: str
    query: dict[str, str]
    headers: dict[str, str]


Responder = Callable[[Seen], Reply]


class FakeAPI:
    """Serves scripted replies and records every request it receives."""

    def __init__(self) -> None:
        self.requests: list[Seen] = []
        self._replies: list[Reply] = []
        self.responder: Responder | None = None
        self.sleeps: list[float] = []
        handler = self._handler()
        self._server = ThreadingHTTPServer(("127.0.0.1", 0), handler)
        self._thread = threading.Thread(
            target=self._server.serve_forever, kwargs={"poll_interval": 0.02}, daemon=True
        )

    @property
    def url(self) -> str:
        host, port = self._server.server_address[:2]
        return f"http://{host!s}:{port}"

    def queue(self, *replies: Reply) -> None:
        self._replies.extend(replies)

    def client(self, **kwargs: Any) -> Client:
        client = Client(base_url=self.url, **kwargs)
        client._transport._sleep = self.sleeps.append
        return client

    def _next(self, seen: Seen) -> Reply:
        self.requests.append(seen)
        if self._replies:
            return self._replies.pop(0)
        if self.responder is not None:
            return self.responder(seen)
        return Reply(500, {"title": "No scripted reply", "code": "TEST"})

    def _handler(self) -> type[BaseHTTPRequestHandler]:
        api = self

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self) -> None:
                parts = urlsplit(self.path)
                query = {k: v[-1] for k, v in parse_qs(parts.query).items()}
                seen = Seen(parts.path, query, {k.lower(): v for k, v in self.headers.items()})
                reply = api._next(seen)
                body = reply.body
                if isinstance(body, (dict, list)):
                    raw = json.dumps(body).encode()
                    content_type = "application/json"
                elif isinstance(body, str):
                    raw = body.encode()
                    content_type = "text/html"
                else:
                    raw = body
                    content_type = "application/json"
                self.send_response(reply.status)
                self.send_header("Content-Type", content_type)
                self.send_header("Content-Length", str(len(raw)))
                for key, value in reply.headers.items():
                    self.send_header(key, value)
                self.end_headers()
                self.wfile.write(raw)

            def log_message(self, format: str, *args: Any) -> None:
                return

        return Handler

    def start(self) -> None:
        self._thread.start()

    def stop(self) -> None:
        self._server.shutdown()
        self._server.server_close()


@pytest.fixture
def api() -> Iterator[FakeAPI]:
    server = FakeAPI()
    server.start()
    try:
        yield server
    finally:
        server.stop()
