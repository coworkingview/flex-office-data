#!/usr/bin/env bash
# Render tmpl/default.php through php -S and save two 1280x800 screenshots.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
port="${PREVIEW_PORT:-8765}"
log="${TMPDIR:-/tmp}/mod-coworkingview-preview.log"
mkdir -p "${root}/screenshots"

php -S "127.0.0.1:${port}" -t "${root}/tools" "${root}/tools/preview.php" >"${log}" 2>&1 &
server=$!
trap 'kill "${server}" 2>/dev/null || true' EXIT

ready=0
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    if curl -fsS "http://127.0.0.1:${port}/?shot=en" >/dev/null; then
        ready=1
        break
    fi
    sleep 0.25
done

if [[ "${ready}" -ne 1 ]]; then
    echo "preview server did not start" >&2
    cat "${log}" >&2 || true
    exit 1
fi

for shot in en de; do
    html="$(curl -fsS "http://127.0.0.1:${port}/?shot=${shot}")"
    if [[ "${html}" != *"Data: CoworkingView"* ]]; then
        echo "${shot} render is missing the attribution link" >&2
        exit 1
    fi
    if [[ "${html}" == *"temporarily unavailable"* || "${html}" == *"vorübergehend nicht erreichbar"* ]]; then
        echo "${shot} render is the error state" >&2
        exit 1
    fi
done

chrome=()
if [[ -x /opt/google/chrome/chrome ]]; then
    chrome=(/opt/google/chrome/chrome)
elif command -v google-chrome >/dev/null 2>&1; then
    chrome=(google-chrome)
elif command -v google-chrome-stable >/dev/null 2>&1; then
    chrome=(google-chrome-stable)
else
    echo "chrome is not installed" >&2
    exit 1
fi

capture() {
    local shot="$1"
    local dest="$2"
    local profile
    profile="$(mktemp -d)"
    # Call the binary directly. The google-chrome wrapper adds a remote
    # debugging port and then does not exit after --screenshot.
    timeout 45 "${chrome[@]}" \
        --headless=new \
        --disable-gpu \
        --no-sandbox \
        --disable-dev-shm-usage \
        --hide-scrollbars \
        --force-device-scale-factor=1 \
        --user-data-dir="${profile}" \
        --window-size=1280,800 \
        --screenshot="${dest}" \
        "http://127.0.0.1:${port}/?shot=${shot}"
    rm -rf "${profile}"
}

capture en "${root}/screenshots/module-en-berlin.png"
capture de "${root}/screenshots/module-de-berlin.png"

php -r '
$files = ["en" => $argv[1], "de" => $argv[2]];
foreach ($files as $label => $path) {
    $info = getimagesize($path);
    if ($info === false || $info[0] !== 1280 || $info[1] < 720) {
        fwrite(STDERR, $label . " screenshot is " . ($info[0] ?? 0) . "x" . ($info[1] ?? 0) . "\n");
        exit(1);
    }
    echo $label, " ", $info[0], "x", $info[1], "\n";
}
' "${root}/screenshots/module-en-berlin.png" "${root}/screenshots/module-de-berlin.png"
