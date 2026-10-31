#!/usr/bin/env python3
"""Check that coworkingview.tar.gz matches the App Store layout."""

import re
import sys
import tarfile

path = sys.argv[1]
with tarfile.open(path, "r:gz") as tar:
    names = tar.getnames()

tops = {name.split("/", 1)[0] for name in names if name}
if tops != {"coworkingview"}:
    raise SystemExit(f"top-level entries must be coworkingview/: {sorted(tops)}")

required = [
    "coworkingview/appinfo/info.xml",
    "coworkingview/appinfo/routes.php",
    "coworkingview/img/app.svg",
    "coworkingview/img/app.png",
    "coworkingview/js/coworkingview-dashboard.mjs",
    "coworkingview/css/coworkingview-dashboard.css",
    "coworkingview/css/dashboard.css",
    "coworkingview/l10n/en.json",
    "coworkingview/LICENSE",
    "coworkingview/README.md",
]
missing = [item for item in required if item not in names]
if missing:
    raise SystemExit("missing from tarball: " + ", ".join(missing))

for name in names:
    if not name.startswith("coworkingview/") and name != "coworkingview":
        raise SystemExit(f"unexpected path: {name}")
    lowered = name.lower()
    if "node_modules" in lowered or "/tests/" in f"/{lowered}" or name.endswith(".map"):
        raise SystemExit(f"release file should not be shipped: {name}")
    if "/src/" in f"/{name}" or name.endswith("composer.json") or name.endswith("package.json"):
        raise SystemExit(f"source file should not be shipped: {name}")

with tarfile.open(path, "r:gz") as tar:
    info = tar.extractfile("coworkingview/appinfo/info.xml").read().decode()
    css = tar.extractfile("coworkingview/css/coworkingview-dashboard.css").read().decode()

for imported in re.findall(r"@import\s+['\"]([^'\"]+)['\"]", css):
    if imported.startswith(("http://", "https://")):
        continue
    target = "coworkingview/css/" + imported.removeprefix("./")
    if target not in names:
        raise SystemExit(f"css import missing from tarball: {target}")

for needle in (
    "<id>coworkingview</id>",
    "<name>CoworkingView</name>",
    "AGPL-3.0-or-later",
    "info@coworkingview.com",
    "https://coworkingview.com",
    "https://github.com/coworkingview/flex-office-data",
    'min-version="33"',
    'max-version="35"',
):
    if needle not in info:
        raise SystemExit(f"info.xml is missing {needle}")

print(f"tarball ok: {path} ({len(names)} entries)")
