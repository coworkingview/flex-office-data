#!/bin/bash
# Build cwv.src.rpm and cwv.rpm inside openSUSE Tumbleweed and run rpmlint.
# GitHub Actions starts this with:
#   docker run --rm -v "$PWD":/src:ro opensuse/tumbleweed \
#     bash /src/integrations/obs/ci-rpmbuild.sh
# The vendor tarball is produced here with cargo vendor. It is not in git.

set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)

if ! command -v zypper >/dev/null 2>&1; then
  echo "error: run this on openSUSE Tumbleweed (zypper is missing)." >&2
  echo "docker run --rm -v \"\$PWD\":/src:ro opensuse/tumbleweed bash /src/integrations/obs/ci-rpmbuild.sh" >&2
  exit 1
fi

zypper --non-interactive --gpg-auto-import-keys refresh
zypper --non-interactive install --no-recommends \
  rpm-build \
  rust \
  cargo \
  cargo-packaging \
  cargo-auditable \
  rpmlint \
  gcc \
  make \
  glibc-devel \
  pkgconf-pkg-config \
  zstd \
  gzip \
  tar \
  curl \
  ca-certificates \
  gawk

# The crate declares rust-version 1.88.
rustc --version
cargo --version

sources=$(mktemp -d)
"$here/vendor.sh" "$sources"

top=$(mktemp -d)
mkdir -p "$top"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}
cp "$here/cwv.spec" "$top/SPECS/cwv.spec"
cp "$sources"/coworkingview-*.crate "$sources"/vendor.tar.zst "$top/SOURCES/"

rpmbuild -ba "$top/SPECS/cwv.spec" \
  --define "_topdir $top" \
  --define "_sourcedir $top/SOURCES"

echo "---- rpmlint ----"
rpmlint_log=$(mktemp)
rpmlint -r "$here/cwv-rpmlintrc" \
  "$top/SPECS/cwv.spec" "$top"/RPMS/*/*.rpm "$top"/SRPMS/*.rpm \
  | tee "$rpmlint_log"
if grep -E ': E: ' "$rpmlint_log"; then
  echo "error: rpmlint reported errors" >&2
  exit 1
fi

shopt -s nullglob
main=()
for rpm in "$top"/RPMS/*/*.rpm; do
  case $rpm in
    *-debuginfo-* | *-debugsource-*) ;;
    *) main+=("$rpm") ;;
  esac
done
if [[ ${#main[@]} -ne 1 ]]; then
  echo "error: expected one installable rpm, found: ${main[*]-none}" >&2
  exit 1
fi

rpm -ivh "${main[0]}"
cwv --version
cwv --help >/dev/null
manpage=$(mktemp)
cwv man >"$manpage"
grep -q 'cwv' "$manpage"
completions=$(mktemp)
cwv completions bash >"$completions"
test -s "$completions"
echo "RPM build, rpmlint, and cwv --version succeeded."
