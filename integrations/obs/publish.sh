#!/bin/bash
# Publish cwv to https://build.opensuse.org/package/show/home:coworkingview/cwv
#
# Credentials are read by osc from ~/.config/osc/oscrc. This script does not
# print that file, does not take a password on the command line, and does
# not create an OBS account.
#
# It replaces the project meta of home:coworkingview with project-meta.xml.
# Run it only when that replacement is what you want.

set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
oscrc=${OSC_CONFIG:-"$HOME/.config/osc/oscrc"}
project=home:coworkingview
package=cwv
crate=coworkingview
version=0.1.0

if [[ ! -f "$oscrc" ]]; then
  echo "error: $oscrc does not exist." >&2
  echo "Install osc, create your OBS account yourself, then log in so osc" >&2
  echo "writes that file. This script does not create an account." >&2
  exit 1
fi

if ! command -v osc >/dev/null 2>&1; then
  echo "error: osc is not installed (openSUSE: zypper install osc)." >&2
  exit 1
fi

# osc reads the file itself. Do not cat it.
export OSC_CONFIG="$oscrc"

sources=$(mktemp -d)
checkout=$(mktemp -d)
trap 'rm -rf "$sources" "$checkout"' EXIT

"$here/vendor.sh" "$sources"

osc meta prj -F "$here/project-meta.xml" "$project"
osc meta pkg -F "$here/package-meta.xml" "$project" "$package"

(
  cd "$checkout"
  osc co "$project" "$package"
)

pkgdir="$checkout/$package"
cp -a "$here/cwv.spec" "$here/cwv.changes" "$here/cwv-rpmlintrc" "$here/_service" "$pkgdir/"
cp -a "$sources/${crate}-${version}.crate" "$sources/vendor.tar.zst" "$pkgdir/"

(
  cd "$pkgdir"
  add=()
  for f in cwv.spec cwv.changes cwv-rpmlintrc _service vendor.tar.zst "${crate}-${version}.crate"; do
    if [[ -f .osc/_files ]] && grep -q "name=\"${f}\"" .osc/_files; then
      continue
    fi
    add+=("$f")
  done
  if [[ ${#add[@]} -gt 0 ]]; then
    osc add "${add[@]}"
  fi
  if [[ -n "$(osc status)" ]]; then
    osc ci --noservice -m "Add cwv ${version}, the CoworkingView Price Index command-line client."
  else
    echo "OBS package ${project}/${package} is already current."
  fi
)

echo "Published ${project}/${package}."
