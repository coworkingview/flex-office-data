# Eclipse Marketplace listing

Paste these values into **Add Content → Solution**. The form fields below are the ones documented by the current Marketplace pages and by the fields shown on a live solution page (the Marketplace Client listing, fetched 1 November 2026).

The old path `https://marketplace.eclipse.org/content/marketplace-listing-guidelines` returns 404. The pages that govern a listing now are:

- [Eclipse Marketplace Publishing Guidelines](https://marketplace.eclipse.org/content/eclipse-marketplace-publishing-guidelines) (what is approved, and that a listing has to be an Eclipse-related product)
- [Marketplace Client Content Inclusion Policy](https://marketplace.eclipse.org/content/marketplace-client-content-inclusion-policy), version 1.1, last updated 14 February 2024 (English, working links, the plug-in must do what the text says, no undisclosed collection of personal data)
- [Eclipse Marketplace Quickstart](https://marketplace.eclipse.org/quickstart) (p2 update site URL and default feature ids, so the Marketplace Client can install into an existing Eclipse)

How this listing follows those rules:

- It is an Eclipse view. It installs into an existing Eclipse. It is not a standalone product.
- The text is English and describes only the view: three monthly desk ranges, refresh, offline snapshot, attribution.
- Homepage, support URL, API URL, and licence URLs were HTTP 200 on 1 November 2026.
- There is no account, no API key, and no telemetry. The only request is an HTTPS GET of the public Price Index with a locale of `en`, `de`, or `es`. That is stated in the long description.
- The licence is MIT, an open-source licence, so the Marketplace Client can list it. CoworkingView is not an Eclipse Foundation member. Leave that checkbox off.
- The update site URL and the feature id are the two fields the Quickstart says the Marketplace Client requires.
- Nothing in the text asks for a higher rank or compares this plug-in with another listing.

Do not submit the listing until https://coworkingview.github.io/flex-office-data/eclipse/updates/ is serving the p2 repository. A moderator checks that the install works. Pages is published from `main`, not from the tag, because the `github-pages` environment only allows that branch.

## Fields

| Field | Value |
|---|---|
| Solution name | CoworkingView Workspace Prices |
| Solution URL / homepage | https://coworkingview.com |
| Organization name | CoworkingView |
| Eclipse Foundation member organization | No |
| Version | 0.1.0 |
| Status | Production/Stable |
| Solution type | This product requires an existing Eclipse installation to function |
| License | MIT |
| Market | Tools |
| Categories | Tools, General Purpose Tools |
| Tags | coworking, price index, workspace |
| Eclipse versions | 2024-12 (4.34), 2025-03 (4.35), 2025-06 (4.36), 2025-09 (4.37), 2025-12 (4.38), 2026-03 (4.39), 2026-06 (4.40), 2026-09 (4.41). Skip a release the form does not list. Do not select anything older than 2024-12. |
| Platforms | Windows, macOS, Linux |
| Minimum Java version | 17 |
| Update site URL | https://coworkingview.github.io/flex-office-data/eclipse/updates/ |
| Feature IDs | com.coworkingview.eclipse.feature |
| Support URL | https://coworkingview.com/en/api |
| Homepage | https://coworkingview.com |
| RSS feed | leave blank |
| Logo | Upload [docs/logo-110x80.png](docs/logo-110x80.png). 110×80, serif black CV, gold dot, off-white. Not the old red mark. A square export of the same mark is [docs/logo-256.png](docs/logo-256.png) if the form asks for a square file. |
| Screenshots | [docs/screenshots/workspace-prices.png](docs/screenshots/workspace-prices.png), [docs/screenshots/workspace-prices-berlin.png](docs/screenshots/workspace-prices-berlin.png) |

Minimum Java is 17 because the plug-in is compiled for Java 17. Eclipse 2024-12 and newer still need a Java 21 runtime to start. If the form has a single “Minimum Java version” and Java 21 is the honest answer for the IDE, choose 21 and keep the description’s sentence that the bytecode is 17.

If Pages did not publish, put this in the update site field instead:

`jar:https://github.com/coworkingview/flex-office-data/releases/download/eclipse-v0.1.0/coworkingview-eclipse-p2.zip!/`

## Short description

Eclipse view of CoworkingView Price Index ranges for hot desks, dedicated desks, and private offices. No API key. By CoworkingView.

## Long description

CoworkingView Workspace Prices is an Eclipse view of the public CoworkingView Price Index. CoworkingView publishes it. Development was AI assisted.

Open it from Window, Show View, Other, CoworkingView. The table lists cities. Columns are the monthly range for a hot desk, a dedicated desk, and a private office, where the index publishes that product. A range is the 25th to 75th percentile. One number means the ends match, or only a median was published. An asterisk means fewer than 10 prices. A dash means the product is not published for that city.

Refresh fetches https://api.coworkingview.com/v1/market/rates over HTTPS. The request sends a locale of en, de, or es, taken from the Eclipse language. It sends nothing else. There is no API key. If the request fails, the view shows a snapshot bundled in the plug-in and says so. The plug-in does not send telemetry and does not store a query.

The attribution line under the table is the credit the API returned, and it links to https://coworkingview.com. Price Index data is CC BY 4.0. Plug-in code is MIT. The view does not copy workspace descriptions, photos, or logos.

Support and the API description: https://coworkingview.com/en/api
Homepage: https://coworkingview.com
