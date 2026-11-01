#!/usr/bin/env bash
# Install the built .oxt into a throwaway profile and evaluate CWV_SOURCE.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OXT="$ROOT/dist/coworkingview-calc-0.1.0.oxt"
if [[ ! -f "$OXT" ]]; then
  echo "missing $OXT — run ./build.sh first" >&2
  exit 1
fi

PROFILE="$(mktemp -d)"
PORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')"
SOFFICE_PID=""
LOG="$PROFILE/soffice.log"

cleanup() {
  if [[ -n "$SOFFICE_PID" ]]; then
    kill "$SOFFICE_PID" >/dev/null 2>&1 || true
    wait "$SOFFICE_PID" >/dev/null 2>&1 || true
  fi
  rm -rf "$PROFILE"
}
trap cleanup EXIT

# LibreOffice starts whichever `python3` is first on PATH, and it inherits
# LD_LIBRARY_PATH. actions/setup-python puts its own interpreter and lib
# directory ahead of Debian's, and unopkg then aborts with std::bad_alloc
# inside the UNO bridge. pyuno is built against /usr/bin/python3.
unset LD_LIBRARY_PATH
unset PYTHONHOME
unset PYTHONPATH
export PATH="/usr/bin:/bin"

export SAL_USE_VCLPLUGIN=svp
export LC_ALL=C.UTF-8
export LANG=C.UTF-8

echo "installing into $PROFILE"
unopkg add -v -s -f \
  -env:UserInstallation="file://${PROFILE}" \
  "$OXT"
unopkg list -env:UserInstallation="file://${PROFILE}" | tee "$PROFILE/unopkg-list.txt"
grep -q "com.coworkingview.calc" "$PROFILE/unopkg-list.txt"

echo "starting soffice on port $PORT"
soffice --headless --nologo --nofirststartwizard --norestore --nolockcheck --nodefault \
  --accept="socket,host=127.0.0.1,port=${PORT};urp;StarOffice.ComponentContext" \
  "-env:UserInstallation=file://${PROFILE}" \
  >"$LOG" 2>&1 &
SOFFICE_PID=$!

ready=0
for _ in $(seq 1 90); do
  if python3 -c "import socket; s=socket.create_connection(('127.0.0.1', ${PORT}), 2); s.close()" >/dev/null 2>&1; then
    ready=1
    break
  fi
  if ! kill -0 "$SOFFICE_PID" >/dev/null 2>&1; then
    echo "soffice exited early" >&2
    cat "$LOG" >&2 || true
    exit 1
  fi
  sleep 1
done
if [[ "$ready" -ne 1 ]]; then
  echo "soffice did not open a socket" >&2
  cat "$LOG" >&2 || true
  exit 1
fi

/usr/bin/python3 "$ROOT/tests/smoke_eval.py" "$PORT"
echo "SMOKE OK"
