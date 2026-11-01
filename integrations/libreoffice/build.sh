#!/usr/bin/env bash
# Build dist/coworkingview-calc-<version>.oxt
# Requires the LibreOffice SDK tool unoidl-write (package libreoffice-dev).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

VERSION="$(
  python3 -c '
import xml.etree.ElementTree as ET
root = ET.parse("description.xml").getroot()
node = root.find("{http://openoffice.org/extensions/description/2006}version")
print(node.attrib["value"])
'
)"

UNOIDL="${UNOIDL_WRITE:-}"
if [[ -z "$UNOIDL" ]]; then
  if command -v unoidl-write >/dev/null 2>&1; then
    UNOIDL="$(command -v unoidl-write)"
  elif [[ -x /usr/lib/libreoffice/sdk/bin/unoidl-write ]]; then
    UNOIDL=/usr/lib/libreoffice/sdk/bin/unoidl-write
  fi
fi
UNO_TYPES="${UNO_TYPES:-/usr/lib/libreoffice/program/types.rdb}"
UNO_OFFAPI="${UNO_OFFAPI:-/usr/lib/libreoffice/program/types/offapi.rdb}"

if [[ -z "$UNOIDL" || ! -f "$UNO_TYPES" || ! -f "$UNO_OFFAPI" ]]; then
  echo "unoidl-write or the LibreOffice type registries were not found." >&2
  echo "Install libreoffice-dev, or set UNOIDL_WRITE, UNO_TYPES and UNO_OFFAPI." >&2
  exit 1
fi

STAGE="$(mktemp -d)"
cleanup() { rm -rf "$STAGE"; }
trap cleanup EXIT

"$UNOIDL" "$UNO_TYPES" "$UNO_OFFAPI" "$ROOT/idl/XCoworkingView.idl" "$STAGE/types.rdb"

mkdir -p \
  "$STAGE/META-INF" \
  "$STAGE/pythonpath" \
  "$STAGE/registration" \
  "$STAGE/pkg-description" \
  "$STAGE/release-notes" \
  "$STAGE/icons"

cp "$ROOT/description.xml" "$STAGE/description.xml"
cp "$ROOT/CalcAddIns.xcu" "$STAGE/CalcAddIns.xcu"
cp "$ROOT/META-INF/manifest.xml" "$STAGE/META-INF/manifest.xml"
cp "$ROOT/coworkingview_calc.py" "$STAGE/coworkingview_calc.py"
cp "$ROOT/pythonpath/coworkingview_api.py" "$STAGE/pythonpath/coworkingview_api.py"
cp "$ROOT/registration/license.txt" "$STAGE/registration/license.txt"
cp "$ROOT/pkg-description/pkg-description.en" "$STAGE/pkg-description/pkg-description.en"
cp "$ROOT/release-notes/release-notes.en.txt" "$STAGE/release-notes/release-notes.en.txt"
cp "$ROOT/icons/icon.png" "$STAGE/icons/icon.png"
cp "$ROOT/icons/icon_hc.png" "$STAGE/icons/icon_hc.png"
cp "$ROOT/LICENSE" "$STAGE/LICENSE"

mkdir -p "$ROOT/dist"
OUT="$ROOT/dist/coworkingview-calc-${VERSION}.oxt"
rm -f "$OUT"
(
  cd "$STAGE"
  zip -r -X -9 "$OUT" . >/dev/null
)

python3 - "$OUT" <<'PY'
import sys
import zipfile

path = sys.argv[1]
with zipfile.ZipFile(path) as archive:
    names = archive.namelist()
required = [
    "description.xml",
    "META-INF/manifest.xml",
    "CalcAddIns.xcu",
    "types.rdb",
    "coworkingview_calc.py",
    "pythonpath/coworkingview_api.py",
    "registration/license.txt",
    "pkg-description/pkg-description.en",
    "release-notes/release-notes.en.txt",
    "icons/icon.png",
    "icons/icon_hc.png",
    "LICENSE",
]
missing = [name for name in required if name not in names]
if missing:
    raise SystemExit("oxt is missing: " + ", ".join(missing))
nested = [name for name in names if name.startswith("/") or name.split("/", 1)[0].endswith(".oxt")]
if any(name.count("/") == 0 and name.endswith("/") for name in names):
    raise SystemExit("unexpected directory-only entries")
print("wrote", path)
print("entries", len(names))
PY
