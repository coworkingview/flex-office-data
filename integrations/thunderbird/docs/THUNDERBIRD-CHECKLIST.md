# Review checklist

Rules that decide whether **CoworkingView – Workspace Prices** (`coworkingview@coworkingview.com`, 0.1.0) can be listed on [addons.thunderbird.net](https://addons.thunderbird.net). Each row is a rule, how this package meets it, the source, and what would get it rejected.

Nothing in this repository submits the add-on or creates an ATN account.

## Manifest and Thunderbird version

| Rule | How we meet it | Source | Rejection risk |
|---|---|---|---|
| New add-ons use Manifest V3. Manifest V2 still uploads (Clean Quote 1.5.0, updated 31 October 2026, is MV2), and Thunderbird 128 is the first release that supports MV3. The current samples and the Thunderbird extension guide default new add-ons to MV3. | `manifest_version` is 3. `strict_min_version` is `128.0`. | [A Guide to Extensions](https://developer.thunderbird.net/add-ons/mailextensions). [Update for Thunderbird 128](https://developer.thunderbird.net/add-ons/updating/tb128). [webext-examples `manifest_v3/messageDisplay`](https://github.com/thunderbird/webext-examples/blob/master/manifest_v3/messageDisplay/manifest.json), which uses the same `message_display_action` shape. | An MV2 add-on is still accepted, but a new one written as MV2 ignores the guide reviewers compare against. |
| `strict_min_version` is a real Thunderbird version. WebExtensions reject `*`. | `128.0`, which is on the [ATN version list](https://addons.thunderbird.net/en-US/thunderbird/pages/appversions/). | Same version list: "WebExtensions will not accept a * in strict_min_version." | `128.*` or `*` as the minimum is rejected by the validator. |
| No `strict_max_version` unless the add-on uses an Experiment. Recent listings set a max on the ATN compatibility form (`*`, or a branch such as `160.*`). That form value is not the same as a manifest cap. | The manifest has no max. There is no Experiment. The upload form can leave compatibility open. | Thunderbird extension guide: a max is usually only needed with Experiments. Official MV3 samples set only `strict_min_version`. | A max of `128.*` would refuse Thunderbird 140 and 144. |
| Use `browser_specific_settings`, not `applications`. | `browser_specific_settings.gecko.id` is `coworkingview@coworkingview.com`. | [MV3 conversion guide](https://webextension-api.thunderbird.net/en/mv3/guides/manifestV3.html). The `applications` key is MV2-only in the current schema. | `applications` on an MV3 manifest is an unsupported key. |
| The id is an email-shaped id on a domain the publisher controls, and it never changes. | `coworkingview@coworkingview.com`. It is not a mailbox. | Extension guide, "browser_specific_settings". | A second upload with a different id splits the listing. |
| Name, author, homepage. | Name `CoworkingView – Workspace Prices` via `__MSG_extensionName__` (English). Author `CoworkingView`. `homepage_url` `https://coworkingview.com`, no `www`. | The English message is the name the user asked to ship. Homepage matches the other packages in this repository. | A `www` host is the wrong canonical site. An empty name fails validation. The schema cap on `name` is 45 characters. The English name is 33. |
| Do not use the Thunderbird trademark in the name unless the name is "Something for Thunderbird". | The name does not contain Thunderbird. | [ATN review policy](https://github.com/thunderbird/atn-review-policy), Content. | "CoworkingView for Thunderbird" would need that exact pattern. We do not use the mark. |

## Permissions

| Rule | How we meet it | Source | Rejection risk |
|---|---|---|---|
| Request only the permissions the feature needs. | `permissions` is `storage`. `host_permissions` is `https://api.coworkingview.com/*`. | [ATN review policy](https://github.com/thunderbird/atn-review-policy), Development Practices. The message-display example that reads a message requests `messagesRead`. This add-on does not read a message, so it does not request that permission. | `messagesRead`, `accountsRead`, `addressBooks`, `tabs`, or `<all_urls>` would force a manual review and contradict the description. |
| The button does not need a permission of its own. The manifest key is the grant. | `message_display_action` and `compose_action`, both with `default_popup` and `default_label`. | [messageDisplayAction](https://webextension-api.thunderbird.net/en/mv3/messageDisplayAction.html): the manifest key is what the API requires. `default_label` exists since Thunderbird 85, so 128 is enough. | Calling `messenger.messages.*` without declaring it, or declaring `compose` in order to read the draft, would be a surprise. |
| `storage` is only the default city, in `storage.local`. | Key `city`. Invalid values fall back to `berlin`. `storage.sync` is not used. | `addon/lib/storage.js`. | Syncing the slug would send it to Mozilla account storage, which the privacy text says we do not do. |
| Firefox's `data_collection_permissions` key is not set. | `strict_min_version` is 128.0. addons-linter 9.9.1 warns if the key is missing, and warns `KEY_FIREFOX_UNSUPPORTED_BY_MIN_VERSION` if the key is present at minimum 128. Thunderbird's own MV3 samples for 128.0 do not set it. `npm run lint` passes `--enable-data-collection-permissions false` and still fails on every other warning. | addons-linter 9.9.1 help and the two warnings observed on 1 November 2026. | Shipping the key makes the linter say the manifest is newer than Thunderbird 128. Shipping it to satisfy a Firefox consent dialog would describe the wrong product. The ATN privacy field is the disclosure. |

## Source, remote code, and libraries

| Rule | How we meet it | Source | Rejection risk |
|---|---|---|---|
| Reviewers must be able to read every file in the xpi. Minified or bundled code needs a source archive and takes longer. Prefer a package that is already the source. | `build.sh` zips `addon/` and `LICENSE`. No webpack, no TypeScript, no minifier. `npm run lint` fails if addons-linter's minified-file heuristic matches. | [Source code submission](https://webextension-api.thunderbird.net/en/mv3/guides/sourceCodeSubmission.html). [Mozilla source-code submission](https://extensionworkshop.com/documentation/publish/source-code-submission/). | A minified `popup.js` without a source archive is rejected. The heuristic false-positives on files whose first 30 lines are almost all unindented. The popup and options pages keep real functions near the top so the heuristic does not flag them. |
| Test fixtures stay out of the xpi. | The zip contains the add-on and `LICENSE` only. Fixtures live in `tests/fixtures/` and are the recorded responses from `spec/fixtures/`. | Source-code guide: test files often fail automated review and should not be in the package. | A fixture with operator text inside the xpi is extra review surface and is not needed at runtime. |
| No remote code. No `eval`. No `innerHTML`. | Scripts are `type="module"` and relative. DOM text is `textContent`. Links are https navigation, not scripts. | [ATN review policy](https://github.com/thunderbird/atn-review-policy), Development Practices. [Avoid innerHTML](https://webextension-api.thunderbird.net/en/mv3/guides/innerHTML.html). | An `https://` script tag, or a library loaded from a CDN, is remote code. |
| No third-party library in the xpi. | `addons-linter` and `jsdom` are devDependencies. They are not copied into `addon/`. There is no `VENDOR.md` because nothing is vendored. | Third-party library policy linked from the review policy. | A vendored minified library needs an exact version URL in `VENDOR.md`. We have none. |
| Strings go through `_locales`. | `default_locale` is `en`. Messages exist for `en`, `de`, and `es`, with the same keys. HTML uses `data-i18n-*`. | [i18n sample](https://github.com/thunderbird/webext-examples/tree/master/manifest_v3/i18n). | Hard-coded English in the popup and untranslated `de`/`es` files fail the "localized listing" expectation and the package test. |

## Data, the API, and privacy

| Rule | How we meet it | Source | Rejection risk |
|---|---|---|---|
| Only call endpoints and fields the public API actually has. | `GET /v1/market/rates` with `locale` and optional `city`. `GET /v1/properties` with `locale`, `city`, `page`, `pageSize`. Parsing follows `spec/SPEC.md` and the Swift and OCaml clients. | `clients/swift/Sources/CoworkingView/Parse.swift`, `clients/ocaml`, `integrations/nuxt/src/runtime/query.ts`. | Inventing a `/v1/prices` route, or a field that is not in the payload, makes the popup lie. |
| The Price Index stays attributed. | `data.attribution` is shown as returned. `data.licenseUrl` is the CC BY 4.0 link when it is https. | CC BY 4.0. The `attribution` field on the rates response. | Replacing the API string with a shorter credit line drops the host and the date the API wrote. |
| Do not copy the catalogue. | Properties uses `pageSize=1`. The code reads `meta.pagination.total` and `meta.citation`. It does not read `data[].title`, images, or logos. | `catalogueNotice` on `GET /v1/properties`. `spec/SPEC.md` section 8. | Rendering listing cards would breach that notice. |
| A missing statistic is not zero. | `p25` / `p75` absent on `byType` and on `dayPass` render as an em dash. An unknown city is an error. | Same rule as the Calc add-in and the spec. | Showing 0 for a missing percentile looks like a real price. |
| The privacy policy field is the full add-on policy, not a link. | [THUNDERBIRD-LISTING.md](THUNDERBIRD-LISTING.md) has the text to paste. It names the two requests, the stored slug, and what is not collected. | [ATN review policy](https://github.com/thunderbird/atn-review-policy), Data Disclosure: the field "cannot be a link to an externally hosted privacy policy" and must be specific to the add-on. | Pasting only https://coworkingview.com/en/privacy fails that rule. That URL returned HTTP 200 on 1 November 2026 and is the website policy (cookies, analytics, accounts). The options page links to it as the site policy. The website policy describes processing this add-on does not do, so it is not the ATN field. |
| The description summarises the same collection. | The summary and the description name `api.coworkingview.com`, the city slug, and that messages are not read. | Same policy: "A summary of this information must be included in the add-on's listing description." | A description that says "nothing is sent" is false. The city slug is sent. |
| No personal data from mail, so no extra opt-in for message content. The install permission prompt is the disclosure for the host permission. | No `messagesRead`. The host permission warning at install names `api.coworkingview.com`. | Review policy, Personal Data and No Surprises. Manual review is required when the add-on asks for messages or contacts. This one does not. | Reading the open message to guess a city would need `messagesRead`, an opt-in, and a different privacy policy. |
| HTTPS only. No cookies. | `https://api.coworkingview.com`, `credentials: "omit"`. | Review policy, Cookies and Additional Privacy Protocols. | `http://` or `credentials: "include"` would attach cookies and fail the policy. |
| One retry on 429 and 5xx. | `Retry-After`, else `RateLimit-Reset`, else 2 seconds, cap 10 seconds, then one retry. | `spec/SPEC.md` section 2. The live rate-limit headers are `ratelimit-*` (120 per 60 seconds), which `Headers.get` matches case-insensitively. | A retry loop would hammer the API. |

## Icons, categories, and the listing shape

| Rule | How we meet it | Source | Rejection risk |
|---|---|---|---|
| Icon sizes the manager and the toolbar actually use. | 16, 32, 48, 64, 96, and 128. The toolbar uses 16 and 32. | Manifest `icons` and `default_icon`. Clean Quote 1.5.0 ships a PNG on the action. | A missing 32px icon is scaled badly on the toolbar. |
| The icon is not a red square. | Serif black "CV" and a gold dot on off-white `#F6F3EC`. `tools/render_icons.py` refuses a red pixel. No logo file was in `/cursor/stores/bot`. | This repository's other integrations avoid a red placeholder. | A red mark is the one icon this project must not ship. |
| Categories match where the button lives. | Message and News Reading (`message-and-news-reading`) and Message Composition (`composition`). | Category slugs from the ATN search API on 1 November 2026. The [version page](https://addons.thunderbird.net/en-US/thunderbird/pages/appversions/) lists those display names. QuickArchiver uses `message-and-news-reading`. Clean Quote uses `composition`. | "Privacy and Security" would be the wrong shelf. The add-on is a price lookup. |
| The button label is the English string "CoworkingView prices". | `buttonLabel`, used as `default_title` and `default_label`. German and Spanish translate it. | `default_label` is the visible toolbar label when the toolbar shows text. The title is the tooltip. | A label that only says the add-on name hides the feature. |

## Upload steps

Do this by hand on [addons.thunderbird.net](https://addons.thunderbird.net). This repository cannot log in.

1. Build `dist/coworkingview-workspace-prices-0.1.0.xpi` with `./build.sh`. Run `npm test` and `npm run lint` first. Both have to pass.
2. Sign in at the developer hub. Submit a new add-on, distribution "On this site".
3. Upload the xpi. If the form asks whether the file contains minified or transpiled code, answer no. Do not attach a source archive. The xpi is the source.
4. Set the name, summary, description, both categories, MIT, homepage, and support URL from [THUNDERBIRD-LISTING.md](THUNDERBIRD-LISTING.md).
5. Paste the privacy policy text from that file into the privacy policy field. Do not paste only the website URL.
6. Upload `docs/screenshots/popup-berlin.png` and `docs/screenshots/options.png`, and the 128px icon if the form asks for one separately.
7. Paste the reviewer notes from the listing file. They include the no-account test steps.
8. Submit. Do not mark it experimental, and do not require payment.

After approval, the public page is `https://addons.thunderbird.net/thunderbird/addon/coworkingview-workspace-prices/` only if the slug is generated from the name. Do not advertise that URL before the listing exists.

## What CI checks

The `thunderbird` job runs `npm ci`, `npm test`, `npm run lint`, and `./build.sh`, then uploads the xpi. `npm test` does not use the network. `npm run lint` requires 0 errors, 0 warnings, and no file classified as minified.
