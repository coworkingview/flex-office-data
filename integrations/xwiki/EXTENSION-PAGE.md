# Extension page draft

Text for a page on https://extensions.xwiki.org. These are the field values. This file is not published by the build.

## Name

CoworkingView Prices

## Summary

Wiki macro that shows CoworkingView Price Index figures for one city.

## Description

XAR extension `com.coworkingview:coworkingview-macro` version 0.1.0. It adds one wiki macro.

- Macro id: `coworkingview`
- Macro name: CoworkingView Prices
- Parameters: `city` (required string) and `limit` (optional string, whole number from 1 to 50)
- Visibility: Global
- Content: no content
- Default category: Content

`city` is trimmed, lowercased, and checked against `^[a-z0-9][a-z0-9._-]*$`. The macro then sends one GET to `https://api.coworkingview.com/v1/market/rates?locale=en&city=<slug>`. That is the Price Index endpoint used by `rates()` in this repository (`spec/SPEC.md` and the Python, Ruby, Java, and Rust clients). `limit` is only how many rows the table shows. It is not a query parameter. The macro does not call any other CoworkingView path.

The table columns are City, Product, Unit, Currency, Median, P25, P75, Sample size, and Low confidence. Low confidence is `yes` when sample size is an integer below 10. Rows come from `figures` when that list is present and not empty, otherwise from `byType`, and then from any other city field that is an object with `median` and `sampleSize`. Unpublished cities produce no rows. Under the table the macro prints the response `attribution` string when it is a string, the response `asOf` when it is a string, and a link to https://coworkingview.com.

The HTTP call is `$xwiki.getURLContent` with a 20 second timeout. That method requires Programming rights. Global visibility requires Programming rights as well. The scripting API uses the wiki HTTP user agent and does not expose the status code, so the macro does not retry.

Example:

```
{{coworkingview city="berlin"/}}
```

```
{{coworkingview city="berlin" limit="3"/}}
```

The page XML uses the `WikiMacroClass` and `WikiMacroParameterClass` fields from an XWiki 16.10.11 export. It does not set `executionIsolated`. The XAR is built with `xwiki-commons-tool-xar-plugin` 16.10.19. Continuous integration runs `mvn -B package` and uploads `coworkingview-macro-0.1.0.xar`. It does not start an XWiki instance.

The macro source is MIT. Price Index figures are not. `spec/SPEC.md` in this repository states that the Price Index is CC BY 4.0. The macro prints the attribution string from the API response.

Developed by CoworkingView (info@coworkingview.com).

Issues: https://github.com/coworkingview/flex-office-data/issues

## Website

https://coworkingview.com

## Source

https://github.com/coworkingview/flex-office-data

The Maven project is `integrations/xwiki` in that repository. SCM URL: https://github.com/coworkingview/flex-office-data/tree/main/integrations/xwiki

## Compatibility

XWiki 16.10+

The macro page uses the WikiMacroClass property set shipped in the XWiki 16.10.11 XAR export (`id`, `name`, `description`, `defaultCategories`, `supportsInlineMode`, `visibility`, `contentType`, `contentJavaType`, `code`, `priority`, `async_enabled`, `async_cached`, `async_context`). Parameter objects use `name`, `description`, `mandatory`, `defaultValue`, and `type`. `$jsontool.fromString` has been in XWiki Standard since 9.9RC1. `$xwiki.getURLContent(String, int)` is the method in the 16.10.19 `com.xpn.xwiki.api.XWiki` class.

## Install

Extension Manager: Administration → Extensions, extension id `com.coworkingview:coworkingview-macro`, version `0.1.0`. The wiki must be able to read a repository that hosts that id. Importing this page from Maven uses the XWiki public repository `https://nexus.xwiki.org/nexus/content/groups/public` only after the artifact has been deployed there. This repository's CI builds the XAR and uploads it as a GitHub Actions artifact; it does not deploy it to that Nexus.

Import the XAR: Administration → Content → Import, upload `coworkingview-macro-0.1.0.xar`, and import the pages. The file is `target/coworkingview-macro-0.1.0.xar` from `mvn -B package` in `integrations/xwiki`.

The user who installs the extension needs Programming rights.

## Other fields

| Field | Value |
|---|---|
| Type | XAR |
| Category | Macro |
| Id | `com.coworkingview:coworkingview-macro` |
| Version | 0.1.0 |
| License | MIT License |
| License URL | https://github.com/coworkingview/flex-office-data/blob/main/integrations/xwiki/LICENSE |
