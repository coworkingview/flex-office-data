/**
 * Runs addons-linter and fails when it reports an error, a warning, or a
 * JavaScript file it thinks is minified. Notices are printed and allowed.
 *
 * --enable-data-collection-permissions is turned off. That check is a Firefox
 * consent key. Present, it is rejected at strict_min_version 128.0. Absent,
 * the default linter warns. Thunderbird 128 samples do not set the key.
 * The add-on discloses its one request in the options page and the listing.
 */

import { spawnSync } from "node:child_process";

const result = spawnSync(
  "addons-linter",
  ["addon", "--output", "json", "--enable-data-collection-permissions", "false"],
  { encoding: "utf8" },
);

if (result.error) {
  console.error(result.error.message);
  process.exit(1);
}

const stdout = result.stdout || "";
const start = stdout.indexOf("{");
if (start === -1) {
  process.stderr.write(result.stderr || "");
  process.stderr.write(stdout);
  process.exit(result.status || 1);
}

const report = JSON.parse(stdout.slice(start));
const errors = report.errors || [];
const warnings = report.warnings || [];
const notices = report.notices || [];
const minified = report.metadata?.unknownMinifiedFiles || [];

console.log(
  JSON.stringify(
    {
      errors: errors.length,
      warnings: warnings.length,
      notices: notices.length,
      unknownMinifiedFiles: minified,
    },
    null,
    2,
  ),
);

for (const item of [...errors, ...warnings]) {
  console.error(`${item.code}: ${item.message} (${item.file || "manifest"})`);
}

if (errors.length || warnings.length || minified.length) {
  process.exit(1);
}

if (result.status !== 0) {
  process.stderr.write(result.stderr || "");
  process.exit(result.status);
}
