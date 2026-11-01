# Backstage plugin directory checklist

Checked on 1 Nov 2026 against the files on `master` of [backstage/backstage](https://github.com/backstage/backstage) and the docs those files publish.

This repository does not publish the npm package and does not open the directory pull request. Both are still a person's job. The steps are at the end.

## Sources

- [Add to Directory](https://github.com/backstage/backstage/blob/master/docs/plugins/add-to-directory.md) (`docs/plugins/add-to-directory.md`). The page is marked legacy and says the directory process is still current. The same text is what [backstage.io/docs/plugins/add-to-directory](https://backstage.io/docs/plugins/add-to-directory/) serves.
- [`scripts/verify-plugin-directory.js`](https://github.com/backstage/backstage/blob/master/scripts/verify-plugin-directory.js) on `master`. CI runs this script. The zod object requires `title`, `author`, `authorUrl` (URL), `category`, `description`, `documentation` (URL), `npmPackageName`, `addedDate` (coerced date), and `status` (`active`, `inactive`, or `archived`). Optional: `iconUrl`, `order`, `staleSince`. Unknown keys are stripped, not rejected.
- [`microsite/src/pages/plugins/index.tsx`](https://github.com/backstage/backstage/blob/master/microsite/src/pages/plugins/index.tsx). Cards are loaded from `microsite/data/plugins/*.yaml`. `inactive` and `archived` are separated. Search matches title, description, category, and author. There is no tags field on the card.
- Recent accepted entry: [`microsite/data/plugins/team-leave-tracker.yaml`](https://github.com/backstage/backstage/blob/master/microsite/data/plugins/team-leave-tracker.yaml), merged in [PR 34896](https://github.com/backstage/backstage/pull/34896) on 20 Jul 2026. Same keys as the zod object, plus no `iconUrl`. [PR 30485](https://github.com/backstage/backstage/pull/30485) (Signadot, 18 Jul 2025) and [PR 32952](https://github.com/backstage/backstage/pull/32952) (community plugins, 2 Jun 2026) landed in the same directory.
- [CONTRIBUTING.md](https://github.com/backstage/backstage/blob/master/CONTRIBUTING.md): DCO (`git commit -s`) and the AI use policy. [Pull request template](https://github.com/backstage/backstage/blob/master/.github/PULL_REQUEST_TEMPLATE.md). The Backstage default branch is `master`.
- Plugin shape: [Building Frontend Plugins](https://github.com/backstage/backstage/blob/master/docs/frontend-system/building-plugins/01-index.md) and [Migrating](https://github.com/backstage/backstage/blob/master/docs/frontend-system/building-plugins/05-migrating.md). `@backstage/cli` 0.36 renamed the new-system template to `frontend-plugin` and kept the old one as `legacy-frontend-plugin`. Published plugins are told to keep the legacy `createPlugin` and add `src/alpha.tsx`.
- Package metadata: [package metadata](https://github.com/backstage/backstage/blob/master/docs/tooling/package-metadata.md). `backstage.role`, `pluginId`, and `pluginPackages` are what `backstage-cli package prepack` checks. `exports` must include `./package.json` and, for the new system, `./alpha`.
- Config: [Defining configuration](https://github.com/backstage/backstage/blob/master/docs/conf/defining.md). External HTTP: [Call existing API](https://github.com/backstage/backstage/blob/master/docs/plugins/call-existing-api.md).

## Directory entry

`docs/BACKSTAGE-DIRECTORY-ENTRY.yaml` is the file to copy to `microsite/data/plugins/coworkingview.yaml`. The filename in this repo is not the filename Backstage loads. Their loader only reads `microsite/data/plugins`.

| Rule | What this entry does |
|---|---|
| One `.yaml` file per plugin, document start `---`. | The entry matches `team-leave-tracker.yaml` field for field, with `iconUrl` added because the guide lists it and this repo already has a mark. |
| `title`, `author`, `authorUrl`. | `CoworkingView`, `CoworkingView`, `https://coworkingview.com`. |
| `category` is one string. | `Discovery`, the category API Docs uses. The script does not keep a fixed list. A brand-new category would still pass and would add a new filter chip. |
| `description` at most 170 characters. The written guide says this. The zod schema does not measure it. The page truncates long text. | 122 characters. |
| `documentation` is a URL, and the guide's example is the plugin README. The submission tip asks for a screenshot in that documentation. | The GitHub README for this plugin, which embeds `integrations/backstage/docs/screenshot.png`. `https://coworkingview.com/en/api` returned 200 on 1 Nov 2026 and is linked from that README. It is the API reference, not the plugin docs, so it is not the `documentation` value. |
| `iconUrl` optional. Rights required. Otherwise the site uses `/img/logo-gradient-on-dark.svg`. | Raw URL of `integrations/nextcloud/coworkingview/img/app.png` (the CV mark already in this repo). It has to be on `main` before the directory pull request, or the image 404s. |
| `npmPackageName` quoted. Scope should match the org. The package must already be public, and its npm page should link back to the repo. | `'@coworkingview/backstage-plugin-coworkingview'`. `package.json` `repository.directory` is `integrations/backstage`. `publishConfig.access` is `public`. |
| `addedDate` quoted `YYYY-MM-DD`. | `'2026-11-01'`. If the directory pull request is opened on a later day, change this to that day before committing it. |
| `status: active`. | Set. `inactive` is for packages with no release in 365 days. |
| `tags` | Not in the current zod schema, not rendered by `plugins/index.tsx`, and not present on the July 2026 entries. An old 2021 New Relic file had `tags`, and that key is now ignored. This entry leaves it out so the file matches the entries CI accepts today. |

`order` is only for Core Features. This plugin is not one.

A directory-only change does not touch a published Backstage package, so it does not need a changeset. [PR 34896](https://github.com/backstage/backstage/pull/34896) did not add one. If the changeset check fails anyway, say that in the pull request. Do not add a changeset "just in case" for a YAML file.

## Plugin package

| Rule | What this package does |
|---|---|
| New frontend system, and legacy `createPlugin` for apps that have not migrated. | `src/alpha.tsx` default-exports `createFrontendPlugin` (`pluginId: coworkingview`, page `/coworkingview`). `src/index.ts` default-exports the legacy plugin with `CoworkingViewPage` and `CoworkingViewCard`. |
| `backstage.role` is `frontend-plugin`. `pluginId` matches `createPlugin` / `createFrontendPlugin`. `pluginPackages` lists this package. | Set in `package.json`. `prepack` checks these. |
| `exports` for `.`, `./alpha`, and `./package.json`. `typesVersions` mirrors them. Entry points point at source; `prepack` rewrites them to `dist`. | Set. |
| `configSchema` is `config.d.ts`, and that file is in `files`. Frontend keys use `@visibility frontend`. | `coworkingview.defaultCity` and optional `coworkingview.baseUrl`. |
| Apache-2.0. Backstage itself is Apache-2.0, and new files in that repo use the Apache header. | `LICENSE` is Apache-2.0. Source files carry the 2026 CoworkingView header. Price Index data stays CC BY 4.0 and is not relicensed. |
| Version `0.1.0`, `homepage` `https://coworkingview.com`. | Set. |
| Tests with `@backstage/test-utils`, fixtures, no network. | `renderInTestApp` and `TestApiProvider`. Fixtures are copies of `spec/fixtures/`. `src/setupTests.ts` replaces `fetch` with a function that throws. |
| `tsc`, lint, test, and build. | `npm run tsc` emits declarations with `tsc` (the CLI has no typecheck command, and `package build` refuses to pack without `dist-types`). `npm run lint`, `npm test`, and `npm run build` call `backstage-cli`. CLI 0.36 also requires `jest` and `@backstage/cli-defaults` as devDependencies. `.npmrc` sets `legacy-peer-deps=true` because that CLI release peers `jsdom@^27` while Jest 30 installs `jsdom` 30. The `backstage` job in `.github/workflows/ci.yml` runs tsc, lint, test, and build and does not change the other jobs. |
| Screenshot from the dev app on fixtures. | `npm start`, then `/coworkingview?fixtures=1`. `dev/index.tsx` serves `src/fixtures/` for the two API paths. The capture is `integrations/backstage/docs/screenshot.png`. |
| Real endpoints only. | `GET /v1/market/rates?locale=en&city=` and `GET /v1/properties?locale=en&city=&page=1&pageSize=10`. Fields follow `spec/SPEC.md`. Photos, logos, and descriptions are dropped. One retry on 429 or 5xx. |

## DCO and AI, for the directory pull request

From CONTRIBUTING.md on 1 Nov 2026:

- Every commit needs a `Signed-off-by` trailer. `git commit -s` adds it. The author line has to be a real identity, here `CoworkingView <info@coworkingview.com>` after `git config user.name` and `user.email`.
- AI assistance is allowed. The pull request description must say the change was written with AI assistance. The person who opens it has to understand the YAML and be able to explain it. A pull request that looks unreviewed can be closed without review.
- Use the pull request template. Do not replace it with a generated summary of the diff. Fill in why the plugin should be listed, attach the screenshot, and tick DCO. The changeset line is not applicable for this YAML file; say so next to the box.
- Keep the description short. Maintainers asked people not to paste a model write-up of the diff.

Suggested body, edited by the person who opens it:

```markdown
## Hey, I just made a Pull Request!

List the CoworkingView frontend plugin in the directory. It shows Price Index medians and a page of spaces for one city, from the public API at api.coworkingview.com.

The package is `@coworkingview/backstage-plugin-coworkingview` (Apache-2.0). Price Index figures are CC BY 4.0 and the plugin prints the API attribution.

This pull request was prepared with AI assistance and reviewed before submission.

#### :heavy_check_mark: Checklist

- [ ] A changeset describing the change and affected packages. Not applicable: this pull request only adds `microsite/data/plugins/coworkingview.yaml`.
- [x] Added or updated documentation
- [ ] Tests for new functionality and regression tests for bug fixes
- [x] Screenshots attached (for UI changes)
- [x] All your commits have a `Signed-off-by` line in the message.
```

Attach `integrations/backstage/docs/screenshot.png`.

## What a person still has to do

Do this after the flex-office-data pull request is on `main`, so the README and icon URLs resolve.

1. `cd integrations/backstage && npm ci && npm run tsc && npm run lint && npm test && npm run build`
2. Confirm the npm org exists and the logged-in user can publish it: `npm whoami` and `npm org ls coworkingview`.
3. Publish. Do not use a tag other than `latest` for 0.1.0.

   ```bash
   cd integrations/backstage
   npm publish --access public
   ```

   `prepack` runs `backstage-cli package prepack`, which rewrites `package.json` for the tarball and `postpack` restores the working tree. Check `https://www.npmjs.com/package/@coworkingview/backstage-plugin-coworkingview` and confirm the repository link points at `integrations/backstage`.
4. Fork [backstage/backstage](https://github.com/backstage/backstage) into the `coworkingview` GitHub org, not a personal account.
5. Branch `add-coworkingview` from upstream `master`.
6. Copy `docs/BACKSTAGE-DIRECTORY-ENTRY.yaml` to `microsite/data/plugins/coworkingview.yaml`. Update `addedDate` if the day has changed.
7. Optional local check, from a full checkout of that fork: `yarn install` then `node ./scripts/verify-plugin-directory.js`.
8. Commit with `git commit -s`. The trailer must match `CoworkingView <info@coworkingview.com>`.
9. Open the pull request against `backstage/backstage` `master` with the template above, the screenshot, and the AI disclosure.
10. Do not comment on other pull requests, and do not send email. Wait for their CI and review.
