#!/usr/bin/env python3
"""Check the l3build CTAN zip against the upload rules.

https://ctan.org/help/upload-pkg requires one top-level directory named
after the package, and no generated files that can be rebuilt from the
sources other than the documentation PDF. Hidden files are rejected.
"""

from __future__ import annotations

import sys
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
LATEX_DIR = HERE.parent

REQUIRED = {
    "coworkingview/README.md",
    "coworkingview/LICENSE",
    "coworkingview/coworkingview.sty",
    "coworkingview/coworkingview-rates.csv",
    "coworkingview/coworkingview-doc.tex",
    "coworkingview/coworkingview-doc.pdf",
}

# Extensions that TeX or l3build would regenerate, or that duplicate the tree.
FORBIDDEN_SUFFIXES = (
    ".aux",
    ".log",
    ".toc",
    ".out",
    ".fls",
    ".fdb_latexmk",
    ".synctex.gz",
    ".hd",
    ".tds.zip",
    ".dtx",
    ".ins",
)


def zip_path() -> Path:
    if len(sys.argv) > 1:
        return Path(sys.argv[1])
    candidates = [
        LATEX_DIR / "coworkingview.zip",
        LATEX_DIR / "build" / "distrib" / "ctan" / "coworkingview.zip",
    ]
    for candidate in candidates:
        if candidate.is_file():
            return candidate
    raise SystemExit("CTAN zip not found. Looked for coworkingview.zip.")


def main() -> int:
    path = zip_path()
    problems: list[str] = []
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
    if not names:
        problems.append("zip is empty")
    files = []
    for name in names:
        if name.endswith("/"):
            continue
        parts = name.split("/")
        if any(part.startswith(".") or part == "__MACOSX" for part in parts):
            problems.append(f"hidden or junk path: {name}")
        if ".." in parts or name.startswith("/"):
            problems.append(f"unsafe path: {name}")
        files.append(name)
        lower = name.lower()
        for suffix in FORBIDDEN_SUFFIXES:
            if lower.endswith(suffix):
                problems.append(f"generated or duplicate file: {name}")
    extra = sorted(set(files) - REQUIRED)
    missing = sorted(REQUIRED - set(files))
    for name in missing:
        problems.append(f"missing: {name}")
    for name in extra:
        problems.append(f"unexpected: {name}")
    if len(files) != len(set(files)):
        problems.append("duplicate names in the zip")
    tops = {name.split("/", 1)[0] for name in files}
    if tops != {"coworkingview"}:
        problems.append(f"top-level entries: {sorted(tops)}")
    if problems:
        print(f"{path} is not a valid CTAN archive:", file=sys.stderr)
        for problem in problems:
            print(f"  {problem}", file=sys.stderr)
        return 1
    print(f"{path}")
    for name in sorted(files):
        print(f"  {name}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
