#!/bin/bash
# Build cwv.src.rpm on Fedora and prove it with rpmbuild --rebuild.
# GitHub Actions runs this inside fedora:latest. The vendor tarball is
# produced here. It is not stored in git.
#
# Usage: integrations/copr/ci-srpm.sh [OUTPUT_DIR]
# Copies the .src.rpm into OUTPUT_DIR when that argument is set.

set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
outdir=${1:-}

if ! command -v dnf >/dev/null 2>&1; then
  echo "error: run this on Fedora (dnf is missing)." >&2
  echo "podman run --rm -v \"\$PWD\":/src:ro fedora:latest bash /src/integrations/copr/ci-srpm.sh" >&2
  exit 1
fi

dnf -y install \
  cargo-rpm-macros \
  cargo \
  rust \
  rpm-build \
  redhat-rpm-config \
  gcc \
  make \
  glibc-devel \
  zstd \
  curl \
  ca-certificates \
  tar \
  gzip \
  findutils

rustc --version
cargo --version

sources=$(mktemp -d)
"$here/vendor.sh" "$sources"

top=$(mktemp -d)
mkdir -p "$top"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}
cp "$here/cwv.spec" "$top/SPECS/cwv.spec"
cp "$sources"/coworkingview-*.crate "$sources"/vendor.tar.zst "$top/SOURCES/"

rpmbuild -bs "$top/SPECS/cwv.spec" \
  --define "_topdir $top" \
  --define "_sourcedir $top/SOURCES"

shopt -s nullglob
srpms=("$top"/SRPMS/*.src.rpm)
if [[ ${#srpms[@]} -ne 1 ]]; then
  echo "error: expected one SRPM, found ${#srpms[@]}" >&2
  exit 1
fi
srpm=${srpms[0]}

# The spec stored in the SRPM must still contain %{?dist}. COPR expands
# it in each chroot. A baked-in .fcNN would ship the same Release everywhere.
if ! rpm2cpio "$srpm" | cpio -i --to-stdout --quiet '*cwv.spec' | grep -q 'Release:[[:space:]]*1%{?dist}'; then
  echo "error: SRPM spec lost %{?dist} on Release" >&2
  exit 1
fi

rpmbuild --rebuild "$srpm"

mapfile -t main < <(find "${HOME}/rpmbuild/RPMS" -type f -name 'cwv-*.rpm' \
  ! -name '*-debuginfo-*' ! -name '*-debugsource-*')
if [[ ${#main[@]} -ne 1 ]]; then
  echo "error: expected one installable rpm, found: ${main[*]-none}" >&2
  exit 1
fi

rpm -Uvh "${main[0]}"
cwv --version
cwv --help >/dev/null
test -x /usr/bin/cwv
test -f /usr/share/zsh/site-functions/_cwv
test -f /usr/share/fish/vendor_completions.d/cwv.fish

if [[ -n "$outdir" ]]; then
  mkdir -p "$outdir"
  cp -a "$srpm" "$outdir/"
  echo "SRPM $outdir/$(basename "$srpm")"
else
  echo "SRPM $srpm"
fi
