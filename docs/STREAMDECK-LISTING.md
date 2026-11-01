# Coworking Prices — Marketplace listing

Copy the fields below into Maker Console. The description's first 250 characters are complete sentences, which is the text search engines use.

Marketplace name checks, the Maker Agreement, gallery screenshots, and the AI declaration are done by a person. See `docs/STREAMDECK-CHECKLIST.md`.

## Name

Coworking Prices

16 characters. Capitalized. It does not include the maker name, the word Plugin, or promotional wording.

## Short description

Live CoworkingView workspace counts and Price Index rates on a Stream Deck key.

Use this only if a form asks for a separate summary. The product description field is the long text below.

## Long description

Paste this as the product description. It is English, between 250 and 1,500 characters, and the first 250 characters are unformatted.

```
Shows live CoworkingView figures on a Stream Deck key. Workspace Count is how many coworking spaces the chosen city lists. Market Rate is a Price Index median, such as the monthly flex desk rate. Press a key to open coworkingview.com in your browser. Requires Stream Deck 7.1 or later, macOS 12 or Windows 10, and an internet connection. No account and no API key. Choose the city in the key settings. Figures refresh about every 30 minutes. Support and the website are https://coworkingview.com.

- Workspace Count reads the catalogue size for the chosen city.
- Market Rate reads one Price Index median: flex desk, fixed desk, or private office per month; a day pass per day; or a meeting room per hour.
- Berlin is the default city. The city list is the cities published on the Price Index.
- Pressing a key opens https://coworkingview.com.

Price Index medians are CC BY 4.0. The plugin logs the attribution string returned with each rates response. It does not display operator photos, descriptions, or listing titles.
```

## Links

| Link | URL |
| --- | --- |
| Website | https://coworkingview.com |
| Support | https://coworkingview.com |
| Privacy | https://coworkingview.com/en/privacy |

The manifest `URL` and `SupportURL` are already `https://coworkingview.com`. Add the privacy policy as an additional link on the product page. There is no `www` host.

## Price

Free. The plugin does not send users to a paywall.

## Tags

Maker Console picks tags from its own list. On plugins accepted in September and October 2026, that list includes Monitoring, Utilities, and Development.

Choose **Monitoring** and **Utilities**. Coworking Prices reads a public JSON API and shows the value on a key, which is the same shape as [Fetcher: JSON & HTML Monitor](https://marketplace.elgato.com/product/fetcher-json-html-monitor-6b6b7390-d39c-44c0-aff6-427c249e2623) (2kit, 21 Sep 2026), [My Tempest](https://marketplace.elgato.com/product/my-tempest-0265c0ce-1dd2-41bf-96d7-002fb0a72b93) (Cath Ellis, 27 Oct 2026), and [PowerCost](https://marketplace.elgato.com/product/powercost-e9ac8303-7ba0-4b67-8760-c153213c9b0e) (Dloper, 1 Oct 2026). Do not type a tag the form does not offer.

## Release notes

```
First release. Workspace Count shows how many coworking spaces a city lists. Market Rate shows a Price Index median. Press a key to open https://coworkingview.com. Requires Stream Deck 7.1 or later.
```

## App icon

Upload `integrations/streamdeck/marketplace/app-icon-288.png`. It is a 288 × 288 PNG of the CoworkingView mark: black serif CV and gold dot on a warm paper background. Do not replace it with a red square, and do not put the word Official on it.

## Thumbnail and gallery

Upload these 1920 × 960 PNGs. They are renderings of neutral rounded keys, labeled RENDERING, with the Berlin figures fetched from the public API. They do not show a branded device.

| File | What it shows |
| --- | --- |
| `integrations/streamdeck/marketplace/thumbnail.png` | Both keys: catalogue total and flex desk median |
| `integrations/streamdeck/marketplace/gallery-keys.png` | The same two titles in a row of blank keys |
| `integrations/streamdeck/marketplace/gallery-workspace-count.png` | Workspace Count |
| `integrations/streamdeck/marketplace/gallery-market-rate.png` | Market Rate |

Regenerate them with `python3 integrations/streamdeck/scripts/make-marketplace.py`. The script reads `GET /v1/properties` and `GET /v1/market/rates` for Berlin at the moment it runs.

## AI declaration

Say in the submission that AI assisted the plugin source, the listing text, the icon layout, and the gallery renderings. The numbers on those renderings are the live API figures. Products created entirely with AI are not eligible.
