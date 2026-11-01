#!/usr/bin/env bash
# Syntax, parser fixtures, and the JED rules that apply to this module.
set -euo pipefail

root="$(cd "$(dirname "$0")" && pwd)"
cd "${root}"

while IFS= read -r -d '' file; do
    php -l "${file}"
done < <(find mod_coworkingview tools tests -name '*.php' -print0)

php tests/parser_test.php
php tools/jed-check.php
