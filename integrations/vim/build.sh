#!/usr/bin/env bash
# Build coworkingview-vim-0.1.0.zip. The archive root is the plugin dirs.
set -euo pipefail

root="$(cd "$(dirname "$0")" && pwd)"
version="0.1.0"
name="coworkingview-vim-${version}.zip"
dest="${root}/dist/${name}"
max_bytes=51200

python3 - "$root" "$dest" << 'PY'
import sys
import zipfile
from pathlib import Path

root = Path(sys.argv[1])
dest = Path(sys.argv[2])
files = [
    "LICENSE",
    "README.md",
    "autoload/coworkingview.vim",
    "doc/coworkingview.txt",
    "doc/tags",
    "plugin/coworkingview.vim",
]
missing = [name for name in files if not (root / name).is_file()]
if missing:
    sys.exit("missing release files: " + ", ".join(missing))

dest.parent.mkdir(parents=True, exist_ok=True)
if dest.exists():
    dest.unlink()

with zipfile.ZipFile(dest, "w") as archive:
    for name in files:
        data = (root / name).read_bytes()
        info = zipfile.ZipInfo(filename=name, date_time=(2026, 1, 1, 0, 0, 0))
        info.compress_type = zipfile.ZIP_STORED
        info.create_system = 3
        info.create_version = 20
        info.extract_version = 20
        info.flag_bits = 0
        info.external_attr = 0o644 << 16
        archive.writestr(info, data)

with zipfile.ZipFile(dest) as archive:
    names = archive.namelist()
if names != files:
    sys.exit("unexpected zip members:\n" + "\n".join(names))
for name in names:
    if name.startswith("/") or name.startswith("integrations/") or ".." in name.split("/"):
        sys.exit("unsafe zip member: " + name)
print("\n".join(names))
PY

size="$(wc -c < "$dest")"
if [[ "$size" -ge "$max_bytes" ]]; then
  echo "refusing to keep ${name}: ${size} bytes is not under 50KB" >&2
  rm -f "$dest"
  exit 1
fi
echo "wrote ${dest} (${size} bytes)"
