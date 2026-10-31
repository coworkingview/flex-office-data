#!/usr/bin/env bash
# Build an unsigned Maven Central bundle zip.
# Central rejects this zip until each artifact has a detached .asc signature.
# See PUBLISHING.md for the signed upload.
set -euo pipefail
cd "$(dirname "$0")"

version=0.1.0
artifact=coworkingview
group_path="io/github/coworkingview/${artifact}/${version}"

mvn -B -DskipTests package

stage="$(mktemp -d)"
base="${stage}/${group_path}"
mkdir -p "${base}"
cp pom.xml "${base}/${artifact}-${version}.pom"
cp "target/${artifact}-${version}.jar" "${base}/"
cp "target/${artifact}-${version}-sources.jar" "${base}/"
cp "target/${artifact}-${version}-javadoc.jar" "${base}/"

for file in "${base}"/*; do
  md5sum "${file}" | awk '{print $1}' > "${file}.md5"
  sha1sum "${file}" | awk '{print $1}' > "${file}.sha1"
done

mkdir -p dist
out="$(pwd)/dist/${artifact}-${version}-bundle.zip"
rm -f "${out}"
( cd "${stage}" && zip -r -X "${out}" io )
rm -rf "${stage}"
echo "wrote ${out}"
unzip -l "${out}"
