# addons.thunderbird.net listing

Paste these fields when uploading `dist/coworkingview-workspace-prices-0.1.0.xpi`. Do not create the developer account from this repository, and do not submit the add-on from CI.

Checked against the public listing API on 1 November 2026 (`/api/v4/addons/search/`). Category slugs below are the ones that API returns for current extensions. Display names are the ones on [Valid Application Versions](https://addons.thunderbird.net/en-US/thunderbird/pages/appversions/).

## Name

CoworkingView – Workspace Prices

The en dash is part of the name. English `extensionName` in the package is the same string.

## Summary

Look up flexible workspace prices for a city from the message or compose window. Public CoworkingView Price Index, CC BY 4.0. Sends the city slug to api.coworkingview.com. Does not read messages.

250 characters is the usual summary limit. This summary is 195 characters.

## Description

CoworkingView prices adds a button to the message window and the compose window. Open it while you are planning a meeting or a trip, pick a city, and read flexible workspace prices for that city.

The figures are the CoworkingView Price Index: median, 25th and 75th percentile, and sample size for a flex desk, fixed desk, private office, day pass, meeting room, and any other product the index publishes for that city. A sample under 10 is marked as low confidence. The price index is CC BY 4.0. The popup shows the attribution text the API returns, unchanged, and links to the licence.

The workspace count is the number of listings in the city. It is not a copy of those listings. Titles, photos, and logos are not shown.

The add-on sends the city slug you pick, and the interface language (English, German, or Spanish), to https://api.coworkingview.com. The requests are GET /v1/market/rates and GET /v1/properties with page 1 and page size 1. The city list is GET /v1/market/rates with the language only. No API key. No message, contact, or account data is read or sent. The default city is stored in Thunderbird on this computer and is not synced.

There is no account to create and nothing to pay. The default city is berlin. Change it in the popup or in the add-on preferences.

Homepage: https://coworkingview.com
Support: https://github.com/coworkingview/flex-office-data/issues
Source of this version: the uploaded xpi. It is the original JavaScript. It is not minified.

## Categories

Pick both. The form's display names and the API slugs:

| Display name | Slug |
|---|---|
| Message and News Reading | `message-and-news-reading` |
| Message Composition | `composition` |

Message and News Reading is the primary category. The same button is on the compose toolbar, so Message Composition is the second.

## License

MIT

The Price Index data is not under the MIT licence. It is CC BY 4.0. Say that in the description, which already does. Do not choose a data licence in the code-licence field.

## URLs

| Field | Value |
|---|---|
| Homepage | https://coworkingview.com |
| Support URL | https://github.com/coworkingview/flex-office-data/issues |
| Support email | Leave empty. Support is the issue tracker. |

## Privacy policy

https://coworkingview.com/en/privacy returned HTTP 200 on 1 November 2026. That page is the CoworkingView website policy (accounts, cookies, analytics on the site). This add-on does not use those. ATN requires the privacy policy field to be the full text of a policy that is specific to the add-on. A link is not accepted there. Paste the text below into the privacy policy field. Keep the website URL in the description and on the options page as the publisher's site policy, not as a substitute for this text.

---

Privacy policy for CoworkingView – Workspace Prices (Thunderbird add-on)

This policy describes only the Thunderbird add-on "CoworkingView – Workspace Prices", id coworkingview@coworkingview.com, published by CoworkingView. It does not describe the website coworkingview.com. The website has its own policy at https://coworkingview.com/en/privacy.

What the add-on does. It shows flexible workspace prices for a city you choose, from the public CoworkingView Price Index, inside a Thunderbird popup.

What is stored. The city slug you save (for example berlin). It is stored with Thunderbird's storage.local on the computer where Thunderbird is installed. It is not synced to a Firefox account, a Thunderbird account, or CoworkingView. Uninstalling the add-on removes it. The add-on stores nothing else. It does not set a cookie.

What is sent, and where. When you open the prices button or the preferences page, Thunderbird sends HTTPS requests to https://api.coworkingview.com, which CoworkingView operates. The requests are:

- GET /v1/market/rates with locale set to en, de, or es, and, when a city is selected, city set to that slug.
- GET /v1/properties with the same locale and city, page=1, and pageSize=1.

locale is chosen from the Thunderbird interface language. A language other than English, German, or Spanish is sent as en. There is no API key. The add-on does not add an identifier, an email address, or the contents of a message.

What is not collected. The add-on does not read messages, contacts, accounts, folders, or browsing history. It does not request permission to do so. It does not collect crash reports, usage statistics, or advertising identifiers. It does not load remote program code.

Why. The city and the language are sent so the public API can return prices and the catalogue count for that city in that language. They are not used for anything else by the add-on.

Who receives it. The requests go to CoworkingView at api.coworkingview.com. The add-on does not send them to anyone else. CoworkingView's handling of API requests is covered by the website policy linked above. The add-on itself does not sell or share the city slug.

How to stop it. Do not open the button, or disable or remove the add-on. There is no separate telemetry switch because there is no telemetry. Changing the default city only changes the slug that is stored and later sent.

Attribution. Price figures are CC BY 4.0. The popup shows the attribution string the API returns.

Contact. https://github.com/coworkingview/flex-office-data/issues

---

## Screenshots

Upload both. They were rendered in headless Chrome from the add-on's popup code and the recorded Berlin API fixture (`spec/fixtures/market_rates_berlin_usd.json` and `spec/fixtures/properties_berlin.json`). They are not a photograph of a Thunderbird window. The caption should say so if the form has a caption field.

| File | What it shows |
|---|---|
| `docs/screenshots/popup-berlin.png` | The prices popup for Berlin, including the attribution line. |
| `docs/screenshots/options.png` | The preferences page: default city and the "What is sent" text. |

The icon for the listing is `addon/icons/icon-128.png`.

## Notes for the reviewer

No account, no password, and no API key. Thunderbird 128 or newer.

1. Install the xpi.
2. Open any message. On the message toolbar, click CoworkingView prices (black "CV" on an off-white icon, gold dot).
3. The popup loads Berlin. The table is medians from GET /v1/market/rates?locale=en&city=berlin (or de or es, following the Thunderbird language). The listing count is meta.pagination.total from GET /v1/properties for that city, page 1, page size 1.
4. The line under the table is the API's attribution string. It must be visible.
5. Open a compose window. The same button is on that toolbar and opens the same popup.
6. Preferences: set the default city. The only saved value is that slug.
7. The add-on does not read the open message. It does not request messages or address books.

The xpi is the source. `build.sh` zips `addon/` and `LICENSE`. It does not minify, bundle, or compile. Please review the JavaScript in the xpi. A separate source archive is not needed. Tests and fixtures are in the public repository and are not inside the xpi, because the source-code guide asks that test fixtures stay out of the submitted package.
