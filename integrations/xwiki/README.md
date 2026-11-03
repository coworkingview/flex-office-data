# CoworkingView Prices

XWiki macro for the public [CoworkingView](https://coworkingview.com) Price Index. The extension id is `com.coworkingview:coworkingview-macro`, version 0.1.0. The macro id is `coworkingview` and the macro name is CoworkingView Prices.

No account and no API key.

## Install

**Extension Manager.** In the wiki, open Administration → Extensions. Install extension id `com.coworkingview:coworkingview-macro`, version `0.1.0`, from a repository that contains this XAR (extensions.xwiki.org after the extension page is published, or a Maven repository configured on the wiki). The user who installs it needs Programming rights.

**Import the XAR.** Build the archive, or take `coworkingview-macro-0.1.0.xar` from the XWiki GitHub Actions artifact. In Administration → Content → Import, upload that file and import `CoworkingView.WebHome` and `CoworkingView.CoworkingViewMacro`.

The macro page is hidden. Its visibility is Global, which requires Programming rights, and the request uses `$xwiki.getURLContent`, which also requires Programming rights.

## Usage

On a page:

```
{{coworkingview city="berlin"/}}
```

Show at most three product rows:

```
{{coworkingview city="berlin" limit="3"/}}
```

| Parameter | Required | Meaning |
|---|---|---|
| `city` | yes | City slug, for example `berlin` or `abu-dhabi`. The macro trims it, lowercases it, and sends it as the `city` query parameter. |
| `limit` | no | Whole number from 1 to 50. Maximum number of rows in the table. Omit it to show every published product. It is not sent to the API. |

The table columns are City, Product, Unit, Currency, Median, P25, P75, Sample size, and Low confidence. Low confidence is `yes` when the sample size is an integer below 10, which is the rule in `spec/SPEC.md`. Product order is the Price Index order from that specification: `flex_desk`, `fix_desk`, `private_office`, `exclusive_bereich`, `day_pass`, `meeting_room`, `event_space`, `virtual_office`, `membership`, then any other product alphabetically.

Figures (or `byType` when `figures` is absent or empty) are monthly. `dayPass`, `meetingRoom`, and any later city field that is an object with `median` and `sampleSize` are included too. `day_pass` is per day, `meeting_room` and `event_space` are per hour, `virtual_office` is per month. Unpublished cities produce no rows.

Under the table the macro prints the response's `attribution` string when it is present, then a link to [https://coworkingview.com](https://coworkingview.com). It also prints `asOf` when that string is present.

## Request

One HTTPS GET, timeout 20 seconds:

`https://api.coworkingview.com/v1/market/rates?locale=en&city=<slug>`

That is `GET /v1/market/rates`, the same endpoint `rates()` uses in `spec/SPEC.md` and in the Python, Ruby, Java, Rust, and other clients in this repository. `locale=en` is sent because the API requires a locale. The macro does not call `/v1/properties` or any other path.

The call goes through XWiki's `getURLContent`. That API uses the wiki's configured HTTP user agent (XWiki's default is `XWikiBot/1.0`) and does not return the status code, so this macro does not retry. Nothing from the calling page is sent. There is no API key.

A failure, a non-JSON body, or a body with no `data` object is a short message plus the link to https://coworkingview.com. The macro does not invent a price.

## Build

The project is a Maven XAR. Dependencies resolve from the XWiki public group `https://nexus.xwiki.org/nexus/content/groups/public`.

```console
mvn -B package
```

The archive is `target/coworkingview-macro-0.1.0.xar`. The XAR plugin version is 16.10.19, and the `WikiMacroClass` / `WikiMacroParameterClass` field lists in the page XML match an XWiki 16.10.11 export of those classes.

## Licence

The macro is [MIT](LICENSE). Price Index figures are not covered by that licence. `spec/SPEC.md` states that the Price Index is CC BY 4.0. The macro prints the attribution string from the response and does not replace it.

Homepage: [https://coworkingview.com](https://coworkingview.com).
