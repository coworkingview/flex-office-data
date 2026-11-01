# Nuxt modules directory checklist

Listing notes for `@coworkingview/nuxt` on [nuxt.com/modules](https://nuxt.com/modules) (`github.com/nuxt/modules`). Nothing in this repository was submitted to nuxt/modules, and the package was not published to npm.

Checked on 2026-11-01 against the live `main` branch of [nuxt/modules](https://github.com/nuxt/modules) and the [module starter](https://github.com/nuxt/starter/tree/module).

## Rules that were checked

`CONTRIBUTING.md` on nuxt/modules returns 404. The contribution rules are in the repository [README](https://github.com/nuxt/modules/blob/main/README.md) (section "Contribution") and in the code that `pnpm sync` runs.

Also read:

- [Module author guide](https://nuxt.com/docs/guide/going-further/modules) and [Create your first module](https://nuxt.com/docs/4.x/guide/modules/getting-started) (starter: `npm create nuxt -- -t module`, `@nuxt/module-builder`, `nuxt-module-build`, `configKey`, playground, Vitest, `prepack`).
- [nuxt/modules `lib/categories.ts`](https://github.com/nuxt/modules/blob/main/lib/categories.ts) for the category list.
- [nuxt/modules `lib/modules.ts`](https://github.com/nuxt/modules/blob/main/lib/modules.ts) and [`lib/utils.ts`](https://github.com/nuxt/modules/blob/main/lib/utils.ts) for sync, the YAML fields, and how `repo` is fetched.
- [nuxt/modules `lib/types.ts`](https://github.com/nuxt/modules/blob/main/lib/types.ts) for `ModuleInfo` and maintainers (`name`, `github`, optional `twitter` / `bluesky`).
- Recent entries in `modules/*.yml`, including `modules/jsonapi.yml` and `modules/api-party.yml` (`category: API & Data Fetching`, `compatibility.nuxt: '>=3.0.0'`, `learn_more: ''`, `requires: {}`) and subdirectory modules `modules/vueuse.yml` (`vueuse/vueuse#main/packages/nuxt`) and `modules/vue-api.yml` (`gaetansenn/vue-api#main/packages/nuxt`, `icon: ''`).
- `.github/workflows/autofix.yml`: on a pull request, `pnpm lint --fix` and `pnpm sync --changed=origin/<base>` run and may push fixes.
- `.github/ISSUE_TEMPLATE/module_request.yml`: maintainers open a pull request directly. An issue is only for asking that someone else's module be listed.
- [Nuxt contribution / AI-assisted contributions](https://nuxt.com/docs/community/contribution#ai-assisted-contributions) and [nuxt/nuxt `AGENTS.md`](https://github.com/nuxt/nuxt/blob/main/AGENTS.md). Comments, issues and pull request descriptions are written by a human. An automated agent does not open the nuxt/modules pull request.

### What the module entry has to satisfy

| Rule | How this repo meets it |
| --- | --- |
| `name` matches `modules/<name>.yml`, lowercase letters, numbers, hyphens and dots | `coworkingview` |
| `npm` is the package name | `@coworkingview/nuxt` |
| `description` says what it does and does not name a Nuxt version (`nuxt 3`, `nuxt3`, `nuxt.js` are warned) | Same sentence as `package.json` `"description"` |
| `category` is one of `lib/categories.ts` | `API & Data Fetching` |
| `compatibility.nuxt` is a semver range | `>=3.0.0` (also `meta.compatibility.nuxt` in `src/module.ts`, which is what `dist/module.json` publishes) |
| `maintainers[].github` | `coworkingview` |
| `type` | `3rd-party`. Sync sets this itself when the repo is not under `nuxt/`, `nuxt-community/`, `nuxt-modules/` or `nuxt-content/` |
| `icon` | Left as `icon: ''`. Sync throws if `icon` is a filename that is not in `nuxt/modules/icons/`. Add a file there first if you want one |
| `website` | `https://coworkingview.com` |
| Starter shape | `defineNuxtModule`, `configKey: 'coworkingview'`, runtime composables, playground, ESLint, Vitest + `@nuxt/test-utils`, MIT `LICENSE`, `CHANGELOG.md`, README badges and quick setup |

### Subdirectory repo field

`pnpm sync` does allow a module that lives in a subdirectory. `fetchGithubPkg` splits on the first `#` and requests:

`https://raw.githubusercontent.com/<org>/<name>/<everything-after-hash>/package.json`

So the branch is required. The README example is `pnpm sync scripts nuxt/scripts#main/packages/script`.

| Value | Request sync makes | Result |
| --- | --- | --- |
| `coworkingview/flex-office-data#integrations/nuxt` | `.../flex-office-data/integrations/nuxt/package.json` | Fails. `integrations` is not a branch |
| `coworkingview/flex-office-data#main/integrations/nuxt` | `.../flex-office-data/main/integrations/nuxt/package.json` | Works |

`docs/NUXT-MODULES-ENTRY.yml` uses the working form. `github` is the repository without the `#main/...` suffix (`https://github.com/coworkingview/flex-office-data`), which is what sync writes.

### Website redirect

`https://coworkingview.com` responds `301` to `https://coworkingview.com/en`. Sync follows redirects and will rewrite `website` to `https://coworkingview.com/en` when autofix runs. The entry file keeps `https://coworkingview.com`, which is the URL this repository publishes. Leave the rewrite in place if autofix commits it, or set `website` to `https://coworkingview.com/en` yourself before opening the pull request so the diff stays still.

Sync also overwrites `website` with `docs` from the published `dist/module.json` when that field exists. This module does not set `docs`, so the YAML `website` stays.

### Maintainer profile

With `GITHUB_TOKEN` set, sync looks up `user(login: coworkingview)` and may replace `name` with the GitHub profile name and add `twitter` or `bluesky`. If `coworkingview` is an organization, that user query fails and the name in the YAML is left as written. Do not invent an `avatar` URL.

## Steps

Do these from a machine where you are logged in as the CoworkingView npm user and the GitHub user that maintains the module. Publish first: sync reads GitHub for `package.json` even before npm has the package, but it only learns compatibility from the published `dist/module.json`.

### 1. Publish to npm

From a clean checkout of the release commit, in `integrations/nuxt`:

```bash
npm ci
npm run prepack
npm publish --access public
```

`publishConfig.access` is already `public`. `prepack` runs `nuxt-module-build prepare` and then `nuxt-module-build build`, and `npm publish` runs `prepack` again. Version `0.1.0` is the first release. Do not run `npm run release` for this publish: that script also runs changelogen, publishes, and pushes git tags.

Confirm `https://www.npmjs.com/package/@coworkingview/nuxt` serves `dist/module.mjs` and `dist/module.json` with `configKey` `coworkingview` and `compatibility.nuxt` `>=3.0.0`.

### 2. Fork nuxt/modules

Fork [github.com/nuxt/modules](https://github.com/nuxt/modules) and clone your fork. You do not need to open an issue first.

```bash
pnpm install
pnpm sync coworkingview coworkingview/flex-office-data#main/integrations/nuxt
```

That creates `modules/coworkingview.yml`. Compare it with `docs/NUXT-MODULES-ENTRY.yml` in this repository. Set `category: API & Data Fetching` if the new-module warning left it empty. Leave `icon` empty unless you add a file under `icons/`.

### 3. Open the pull request yourself

A human who maintains CoworkingView opens the pull request. Write the description in your own words. nuxt/nuxt's policy is that pull request descriptions are not written by an LLM, and this listing was not opened from an agent.

Say both of these in the description:

- **Affiliation.** You are CoworkingView (or you work for CoworkingView). CoworkingView publishes the API at `api.coworkingview.com` and the package `@coworkingview/nuxt`.
- **AI disclosure.** The module in `coworkingview/flex-office-data` was drafted with AI assistance and reviewed by the maintainer before publish. Say which tool, and that you can explain the code.

Suggested title: `feat: add coworkingview module`.

The pull request diff is `modules/coworkingview.yml` (and `icons/…` only if you added an icon). Autofix may push formatting or the website redirect. Read that commit before you merge.

## Module behaviour the listing does not need to repeat

- `GET /v1/properties` and `GET /v1/market/rates` only. Public, no key.
- Composables `useCoworkingProperties` and `useCoworkingRates` use `useFetch` and Nuxt's `$fetch`.
- Tests use `@nuxt/test-utils` and the fixtures in `spec/fixtures/`. They do not call the live API.
