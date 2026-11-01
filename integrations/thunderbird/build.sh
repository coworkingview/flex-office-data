#!/bin/sh
# Pack the MailExtension. This copies files into a zip; it does not compile,
# bundle, or minify. The .xpi is the source a reviewer reads.
set -eu
cd "$(dirname "$0")"
python3 - <<'PY'
import json
import zipfile
from pathlib import Path

root = Path(".").resolve()
addon = root / "addon"
manifest = json.loads((addon / "manifest.json").read_text(encoding="utf-8"))
version = manifest["version"]
out_dir = root / "dist"
out_dir.mkdir(parents=True, exist_ok=True)
out = out_dir / f"coworkingview-workspace-prices-{version}.xpi"
if out.exists():
    out.unlink()

def files(directory):
    for path in sorted(directory.rglob("*")):
        if path.is_file() and path.name != ".DS_Store":
            yield path

with zipfile.ZipFile(out, "w", compression=zipfile.ZIP_DEFLATED) as archive:
    for path in files(addon):
        archive.write(path, path.relative_to(addon).as_posix())
    archive.write(root / "LICENSE", "LICENSE")

with zipfile.ZipFile(out) as archive:
    names = archive.namelist()
if "manifest.json" not in names or "LICENSE" not in names:
    raise SystemExit("manifest.json or LICENSE is missing from the archive root")
banned = ("tests/", "docs/", "node_modules/", "tools/")
if any(name.startswith(banned) or "/node_modules/" in name for name in names):
    raise SystemExit("archive contains files that are not part of the add-on")
print(out)
PY
