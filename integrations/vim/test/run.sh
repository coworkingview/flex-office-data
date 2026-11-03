#!/usr/bin/env bash
# Run vader.vim against integrations/vim. VIM_BIN selects vim or nvim.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
repo="$(cd "$root/../.." && pwd)"
vader="${VADER_RTP:-/tmp/vader.vim}"
if [[ ! -f "$vader/plugin/vader.vim" ]]; then
  git clone --depth 1 https://github.com/junegunn/vader.vim.git "$vader"
fi

editor="${VIM_BIN:-vim}"
startup_log="$(mktemp)"
rm -f "$startup_log"
vimrc="$(mktemp)"
trap 'rm -f "$vimrc" "$startup_log"' EXIT

cat > "$vimrc" << EOF
set nocompatible
set nomore
set hidden
filetype plugin indent on
set rtp^=${vader}
set rtp^=${root}
let g:coworkingview_curl = '${root}/test/fake-curl'
let \$COWORKINGVIEW_CURL_LOG = '${startup_log}'
let g:coworkingview_test_startup_log = '${startup_log}'
EOF

cd "$repo"
unset COWORKINGVIEW_API_URL || true

name="$(basename "$editor")"
if [[ "$name" == nvim || "$name" == *nvim* ]]; then
  "$editor" --headless -Nu "$vimrc" -n \
    -c "Vader! ${root}/test/rates.vader"
else
  "$editor" -Nu "$vimrc" -n --not-a-term \
    -c "Vader! ${root}/test/rates.vader"
fi
