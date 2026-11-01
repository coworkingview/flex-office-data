#!/usr/bin/env bash
# Build mod_coworkingview-1.0.0.zip. The manifest is at the root of the zip.
set -euo pipefail

root="$(cd "$(dirname "$0")" && pwd)"
version="1.0.0"
name="mod_coworkingview-${version}.zip"
dist="${root}/dist"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

cp -a "${root}/mod_coworkingview/." "${stage}/"
find "${stage}" -name '.DS_Store' -delete

if find "${stage}" -type f \( -name '*.sh' -o -name '*.exe' -o -name '*.bat' \) | grep -q .; then
    echo "refusing to pack an executable script" >&2
    exit 1
fi

mkdir -p "${dist}"
rm -f "${dist}/${name}"

(
    cd "${stage}"
    zip -qr "${dist}/${name}" .
)

php "${root}/tools/jed-check.php" "--zip=${dist}/${name}"
echo "wrote ${dist}/${name}"
