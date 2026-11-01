"""Fill the Read the Docs pages from the canonical Markdown sources.

Read the Docs does not reliably follow symlinks, so ``docs/`` holds real files
and this hook replaces each page with the README or spec it publishes. Relative
links that would leave the site are pointed at the matching page or at GitHub.
"""

from __future__ import annotations

import re

from pathlib import Path

_REPO = "https://github.com/coworkingview/flex-office-data"

# Path under docs/ -> path relative to the repository root.
_SOURCES: dict[str, str] = {
    "index.md": "README.md",
    "python.md": "python/README.md",
    "r.md": "r/README.md",
    "cli.md": "rust/README.md",
    "ocaml.md": "clients/ocaml/README.md",
    "spec.md": "spec/SPEC.md",
}

# Link targets that are not themselves documentation pages.
_LINK_REWRITES: dict[str, dict[str, str]] = {
    "README.md": {
        "python/": "python.md",
        "r/": "r.md",
        "rust/": "cli.md",
        "clients/ocaml/": "ocaml.md",
        "spec/SPEC.md": "spec.md",
        "spec/": f"{_REPO}/tree/main/spec",
        "CONTRIBUTING.md": f"{_REPO}/blob/main/CONTRIBUTING.md",
    },
    "rust/README.md": {
        "LICENSE": f"{_REPO}/blob/main/rust/LICENSE",
    },
    "clients/ocaml/README.md": {
        "LICENSE": f"{_REPO}/blob/main/clients/ocaml/LICENSE",
        "CHANGES.md": f"{_REPO}/blob/main/clients/ocaml/CHANGES.md",
        "../../docs/OPAM-CHECKLIST.md": "OPAM-CHECKLIST.md",
    },
}

_LINK = re.compile(r"\]\(([^)\s]+)\)")


def _rewrite(text: str, mapping: dict[str, str]) -> str:
    def repl(match: re.Match[str]) -> str:
        dest = match.group(1)
        rewritten = mapping.get(dest)
        if rewritten is None:
            return match.group(0)
        return f"]({rewritten})"

    return _LINK.sub(repl, text)


def on_page_markdown(markdown, page, config, files, **kwargs):
    source = _SOURCES.get(page.file.src_uri)
    if source is None:
        return markdown
    root = Path(config.config_file_path).resolve().parent
    text = (root / source).read_text(encoding="utf-8")
    mapping = _LINK_REWRITES.get(source)
    if mapping:
        text = _rewrite(text, mapping)
    return text
