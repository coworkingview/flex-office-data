# Marketplace review checklist

Checked against the Matomo 5.x and current distribution guides on 2026-11-01, and against three small plugins accepted on the Marketplace in 2026:

- [WeatherWidget](https://github.com/Chardonneaur/WeatherWidget) ([listing](https://plugins.matomo.org/WeatherWidget)), an external-API dashboard widget, updated February 2026
- [GithubMarketplace](https://github.com/Chardonneaur/GithubMarketplace), an integration plugin, updated March 2026
- [CustomWidgets](https://plugins.matomo.org/CustomWidgets) and [GeneratedInsights](https://plugins.matomo.org/GeneratedInsights), dashboard widgets updated in 2026

Rules below are from:

- [Distributing your plugin](https://developer.matomo.org/guides/distributing-your-plugin) (the page the docs site serves; the examples there use the current major)
- [Matomo 5.x copy of the same guide](https://github.com/matomo-org/developer-documentation/blob/live/docs/5.x/distributing-your-plugin.md)
- [Plugin directory structure](https://developer.matomo.org/guides/plugin-directory-structure)
- [New plugin checklist](https://developer.matomo.org/guides/maintaining-plugins) (written for Matomo core maintainers; the file list still applies)

| Rule | How this plugin satisfies it |
|---|---|
| Unique name, starts with a capital letter, letters and digits only, at most 60 characters, and does not contain Matomo, Piwik, Analytics, Core, or Plugin. [Guide](https://developer.matomo.org/guides/distributing-your-plugin) | `name` is `CoworkingView`. `https://plugins.matomo.org/CoworkingView` returned 404 on 2026-11-01, so no public listing used this name that day. |
| `README.md` and `plugin.json` exist. The Marketplace page shows the text between `## Description` and the next `##`. | Both files are at the plugin root. The external-call notice, the query table, and the link to https://coworkingview.com are inside `## Description`. |
| `plugin.json` is valid JSON with `description` of at most 150 characters, semantic `version`, `keywords` limited to letters, numbers, hyphens, and dots, `license`, `homepage`, and at least one author `name`. | Version `0.1.0`. Description is 97 characters and names `api.coworkingview.com`. Keywords match WeatherWidget's style (`widget`, `dashboard`, plus topic words). License `GPL-3.0+`. Homepage `https://coworkingview.com`. Author name, email, and homepage are set. |
| `require.matomo` has a lower and an upper bound. The [5.x guide](https://github.com/matomo-org/developer-documentation/blob/live/docs/5.x/distributing-your-plugin.md) sample is `>=5.0.3,<6.0.0-b1`; its complete example is `>=5.0.0` with no upper bound, which contradicts that page's own "lower and upper limit" sentence. The [live v6 page](https://developer.matomo.org/guides/distributing-your-plugin) sample is `>=6.0.0-b1,<7.0.0-b1`. WeatherWidget and GithubMarketplace, both accepted for Matomo 5, use `>=5.0.0-b1,<6.0.0-b1`. | Same range as those two plugins, because this plugin targets Matomo 5. PHP `>=8.1.0` matches WeatherWidget and the v6 sample. GithubMarketplace omits `php`; declaring it is stricter and still valid. |
| `theme` is false for a plugin. WeatherWidget and GithubMarketplace set it. | `"theme": false`. |
| `category` is one of customisation, database, development, insights, integration, security. | `integration`, same value as GithubMarketplace. This widget reads an external API; it is not a Matomo report. |
| `support` may include email, issues, source, and docs. | Email `info@coworkingview.com`, issues `https://github.com/coworkingview/flex-office-data/issues`, source and docs point at this folder in the flex-office-data repository. Empty support keys are omitted so the Support tab does not show blank links. |
| `LICENSE` at the plugin root, and the same license name in `plugin.json`. [Maintainer checklist](https://developer.matomo.org/guides/maintaining-plugins) | `LICENSE` is the GPL-3.0 text. `license` is `GPL-3.0+`, which is in the guide's allow-list. Some accepted plugins use the display string `GPL v3+`; that string is not in the allow-list, so it is not used here. |
| `CHANGELOG.md`, `docs/index.md`, and `docs/faq.md` are recommended and become Marketplace tabs. [Directory structure](https://developer.matomo.org/guides/plugin-directory-structure) | All three exist. The FAQ tab text is `docs/faq.md`. This checklist is a separate file and is not `docs/index.md`, so it does not replace the Documentation tab. |
| Screenshots, if present, live in `screenshots/`, use only letters, numbers, underscores, and dashes, and end in `.png`, `.jpg`, or `.jpeg`. A cover image is `screenshots/_cover.png` at 880×480. WeatherWidget ships `screenshots/WeatherWidget_dashboard.png` and `screenshots/_cover.png`. | No `screenshots/` directory. See the rejection notes below. |
| Free plugins are GPL-3.0-compatible and are not obfuscated. | Source is plain PHP, Twig, CSS, and JSON. No packed or encoded code. |
| No phoning home without disclosure. External data must be explained in the admin screens or the description, including what is sent where. [Rules for plugins](https://developer.matomo.org/guides/distributing-your-plugin) | The `## Description` section (the Marketplace page), both city settings, the widget footer, and `docs/faq.md` name `api.coworkingview.com` and the two requests. Only the chosen city is taken from settings. `locale=en` and `pageSize=1` are fixed. No visitor id, user id, email, or page URL is sent. Precedent: WeatherWidget's FAQ "Does this plugin send data to external services?". |
| Images and scripts are part of the plugin. Do not ship a library Matomo already includes. | No JavaScript file, no `tracker.js`, and no third-party PHP library. HTTP uses `Piwik\Http`. Cache uses `Piwik\Cache`. CSS is `stylesheets/widget.css`, registered with `AssetManager.getStylesheetFiles`. |
| README, the Marketplace page, and translation files must not contain sponsored links. | Links to https://coworkingview.com are the author homepage and the Price Index attribution. There are no affiliate parameters and the word "sponsored" is not used. |
| Do not use Matomo or Piwik in a domain you do not own. [Trademark rule](https://matomo.org/trademark/) | Homepage and links use `coworkingview.com`. |
| Publishing reads `plugin.json` from the GitHub repository root and learns about releases from the webhook `https://plugins.matomo.org/postreceive-hook` plus a tag. A missing `plugin.json` is a known rejection. | This folder is self-contained so it can be the root of `coworkingview/plugin-CoworkingView`. Do not point that webhook at the flex-office-data monorepo. |

## What could still get a review rejected

**The widget is not an analytics report.** WeatherWidget (weather from Open-Meteo) and CustomWidgets (arbitrary HTML) were accepted in 2026 as optional dashboard widgets. This plugin follows that shape: one widget, system and personal settings, no tracker, category `integration`. The description says it is a price widget, not a Matomo report.

**It calls another website whenever the widget is shown.** The phoning-home rule forbids quietly sending user data. It allows an external data feed when the description or the admin screen says what is sent where. WeatherWidget fetches Open-Meteo on dashboard view after the user adds the widget and saves a location. This plugin fetches CoworkingView only after the widget is on a dashboard, and only for the saved city. The Marketplace description itself names the host, which is the text reviewers see first. Failures stay on the dashboard instead of breaking the page.

**There is no screenshot.** The guide recommends screenshots and does not list a missing `screenshots/` directory as a validation error. A file that is not a real Matomo screen would still be published, with the filename as the caption. This repository does not include one. If review asks for it, add a capture from a Matomo 5 dashboard as `screenshots/CoworkingView_dashboard.png`, and a real 880×480 cover as `screenshots/_cover.png`.

**The name check was a 404, not a reservation lookup.** Check `https://plugins.matomo.org/CoworkingView` again on the day the plugin repository is registered.

**`support.source` points at flex-office-data.** That is the correct tree today. When the folder is copied to its own repository, change `support.source` and `support.docs` to that repository before tagging `0.1.0`. Tagging the monorepo will not publish the plugin, because `plugin.json` is not at that repository's root.

**The default developer docs now show Matomo 6.** On 2026-11-01, [developer.matomo.org/guides/distributing-your-plugin](https://developer.matomo.org/guides/distributing-your-plugin) is the v6 page and its sample range is `>=6.0.0-b1,<7.0.0-b1`. This plugin stays on Matomo 5, using the 5.x guide and the range WeatherWidget and GithubMarketplace already ship. A request to retarget Matomo 6 is a new major, not a metadata fix.

**PHP 8.1 is stricter than Matomo 5's oldest PHP.** Matomo 5.0 can run on PHP 7.2. WeatherWidget and GeneratedInsights require PHP 8.1, and this plugin does too. An install on PHP 7.2, 7.3, 7.4, or 8.0 will refuse the plugin. The PHP itself does not use 8.1-only syntax.

**Matomo for WordPress was not installed here.** `wordpress-compatible` is left unset, which the guide says defaults to compatible. The plugin uses the widget, settings, HTTP, and cache APIs. It was not run inside Matomo for WordPress. If that embed rejects it, set `"wordpress-compatible": false` rather than claiming support.

**The widget was not clicked inside Matomo.** `php -l`, `plugin.json` checks, and `tests/parser.php` ran. They do not boot Matomo, so the settings forms and the Twig render are untested in a browser.
