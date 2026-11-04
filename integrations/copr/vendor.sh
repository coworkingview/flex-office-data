#!/bin/bash
# Build the two sources cwv.spec expects:
#   coworkingview-0.1.0.crate   the published crate
#   vendor.tar.zst              Cargo.lock, .cargo/config.toml, vendor/
#
# .cargo/config.toml is the snippet `cargo vendor` prints. It replaces
# crates.io with the vendored directory so `cargo build --offline` works.
# The tarball is not stored in git. Usage: integrations/copr/vendor.sh OUTPUT_DIR

set -euo pipefail

crate=coworkingview
version=0.1.0
sha256=d1f5b5cad9a1738c9a0048ec223989b3ed06bb27d6bd14f5176ee583c72b43b4
url="https://static.crates.io/crates/${crate}/${crate}-${version}.crate"

if [[ $# -ne 1 ]]; then
  echo "usage: $0 OUTPUT_DIR" >&2
  exit 2
fi

outdir=$1
mkdir -p "$outdir"
outdir=$(cd "$outdir" && pwd)

for cmd in curl tar zstd cargo sha256sum; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "error: $cmd is required" >&2
    exit 1
  fi
done

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

partial="$tmp/${crate}-${version}.crate"
curl -fsSL --retry 5 --retry-delay 2 -o "$partial" "$url"
echo "${sha256}  ${partial}" | sha256sum -c -
install -m 0644 "$partial" "$outdir/${crate}-${version}.crate"

mkdir -p "$tmp/extract"
tar -xzf "$partial" -C "$tmp/extract"
srcdir="$tmp/extract/${crate}-${version}"
test -f "$srcdir/Cargo.toml"
test -f "$srcdir/Cargo.lock"

(
  cd "$srcdir"
  if cargo vendor --help | grep -q -- '--versioned-dirs'; then
    cargo vendor --locked --versioned-dirs vendor >"$tmp/vendor-config.toml"
  else
    cargo vendor --locked vendor >"$tmp/vendor-config.toml"
  fi
)

if ! grep -q '^\[source\.crates-io\]' "$tmp/vendor-config.toml"; then
  echo "error: cargo vendor did not print a [source.crates-io] config" >&2
  cat "$tmp/vendor-config.toml" >&2
  exit 1
fi
if ! grep -q 'directory = "vendor"' "$tmp/vendor-config.toml"; then
  echo "error: cargo vendor config does not point at vendor/" >&2
  cat "$tmp/vendor-config.toml" >&2
  exit 1
fi

stage="$tmp/stage"
mkdir -p "$stage/.cargo"
cp -a "$srcdir/Cargo.lock" "$stage/Cargo.lock"
mv "$srcdir/vendor" "$stage/vendor"
# Drop leading blank lines. This is the file unpacked as .cargo/config.toml.
sed -e '/./,$!d' "$tmp/vendor-config.toml" >"$stage/.cargo/config.toml"

tar -cf - \
  --sort=name \
  --owner=0 --group=0 --numeric-owner \
  -C "$stage" . \
  | zstd -T0 -19 -o "$outdir/vendor.tar.zst"

echo "wrote $outdir/${crate}-${version}.crate"
echo "wrote $outdir/vendor.tar.zst"
