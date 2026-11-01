#!/usr/bin/env bash
# Install Joomla 5 and JED Checker 2.4.4, then check the module zip.
# JOOMLA_BASE skips the install when that site already has com_jedchecker.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
zip="${1:-${root}/dist/mod_coworkingview-1.0.0.zip}"
report="${2:-${root}/docs/jed-checker-report-1.0.0.html}"

if [[ ! -f "${zip}" ]]; then
    (cd "${root}" && ./build.sh)
fi

if [[ -n "${JOOMLA_BASE:-}" && -f "${JOOMLA_BASE}/configuration.php" && -d "${JOOMLA_BASE}/administrator/components/com_jedchecker" ]]; then
    JOOMLA_BASE="${JOOMLA_BASE}" php "${root}/tools/run-jedchecker.php" "${zip}" "${report}"
    exit $?
fi

joomla_version="${JOOMLA_VERSION:-5.4.10}"
jed_tag="${JEDCHECKER_TAG:-2.4.4}"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

curl -fsSL -o "${work}/joomla.zip" \
    "https://github.com/joomla/joomla-cms/releases/download/${joomla_version}/Joomla_${joomla_version}-Stable-Full_Package.zip"
mkdir "${work}/site"
unzip -q "${work}/joomla.zip" -d "${work}/site"

curl -fsSL -o "${work}/jedchecker.zip" \
    "https://github.com/joomla-extensions/jedchecker/archive/refs/tags/${jed_tag}.zip"

php "${work}/site/installation/joomla.php" install --no-interaction \
    --site-name="CoworkingView JED Checker" \
    --admin-user="CoworkingView" \
    --admin-username="admin" \
    --admin-password="${JOOMLA_ADMIN_PASSWORD:-JedChecker-temp-1}" \
    --admin-email="info@coworkingview.com" \
    --db-type=mysqli \
    --db-host="${JOOMLA_DB_HOST:-127.0.0.1}" \
    --db-user="${JOOMLA_DB_USER:-joomla}" \
    --db-pass="${JOOMLA_DB_PASS:-joomla}" \
    --db-name="${JOOMLA_DB_NAME:-joomla}" \
    --db-prefix="${JOOMLA_DB_PREFIX:-jci_}" \
    --db-encryption=0

php "${work}/site/cli/joomla.php" extension:install --path="${work}/jedchecker.zip"

JOOMLA_BASE="${work}/site" php "${root}/tools/run-jedchecker.php" "${zip}" "${report}"
