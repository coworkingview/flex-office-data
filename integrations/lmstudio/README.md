# CoworkingView workspace prices

Tools for [LM Studio](https://lmstudio.ai) that look up flexible-workspace prices and listings from the public [CoworkingView](https://coworkingview.com) API. No API key.

Ask for a city and the model can report the Price Index (median, the 25th to 75th percentile, and the sample size) and link a few published listings. Figures are indicative aggregates, not a quote from an operator.

This plugin was built with AI assistance. CoworkingView maintains it.

CoworkingView is not affiliated with, endorsed by, or sponsored by Element Labs or LM Studio. LM Studio is named here only as the application this plugin runs in.

## Tools

| Tool | What it calls | What you get |
|---|---|---|
| `get_workspace_prices` | `GET https://api.coworkingview.com/v1/market/rates` | Median, p25 and p75 when the API published them, sample size, and the CC BY attribution. A missing percentile is left empty, not reported as zero. A sample under 10 is low confidence. |
| `search_workspaces` | `GET https://api.coworkingview.com/v1/properties` | Up to 10 listings in one city, each with a link on coworkingview.com. Photos, logos, and descriptions are not returned. |
| `list_cities` | `GET https://api.coworkingview.com/v1/market/rates` with no city | Published city slugs. Unpublished cities are omitted. |

`city` is a slug such as `berlin` or `abu-dhabi`. `product` is optional: `flex_desk`, `fix_desk`, `private_office`, `exclusive_bereich`, `day_pass`, `meeting_room`, `event_space`, `virtual_office`, or `membership`. `language` is optional: `en`, `de`, or `es`.

Every tool result includes `Data: CoworkingView (https://coworkingview.com)` and a link to https://coworkingview.com. Price Index results also include the attribution string and licence URL returned by the API.

## Example prompts

- What is the median price of a flex desk in Berlin, and what is the 25th to 75th percentile?
- Compare day-pass prices in Madrid and Berlin. Include the sample size.
- Which cities does CoworkingView publish a price index for?
- Find coworking spaces in Berlin and give me the links.

## Settings

In the plugin sidebar for the chat:

- **Default language** — `en`, `de`, or `es`. Used when a tool call does not set `language`.
- **Request timeout (seconds)** — how long one request may take. The default is 20. A 429 or 5xx response is retried once.

## Privacy

The tools send only the city, the optional product, and the language to `https://api.coworkingview.com`. Search also sends fixed paging parameters (`page=1`, `pageSize=10`, `sortBy=date-desc`). No API key is stored or sent. The chat transcript, local files, and account data are not sent. The plugin does not write data to disk.

The website privacy policy at https://coworkingview.com/en/privacy describes the website. It is not a description of this plugin.

## Links

- Homepage: https://coworkingview.com
- API documentation: https://coworkingview.com/en/api

## Licence

The plugin code is MIT. See [LICENSE](LICENSE).

The Price Index data is not covered by the MIT licence. It is [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Keep the attribution `Data: CoworkingView (https://coworkingview.com)` with anything you republish, and keep the attribution string the API returns.

Catalogue listings (names, descriptions, images, logos, and prices of individual spaces) are not licensed for reuse. The tools return names and links so a chat can point at a listing page. Systematic extraction of the catalogue is not permitted. The API's catalogue notice is included in `search_workspaces` results.
