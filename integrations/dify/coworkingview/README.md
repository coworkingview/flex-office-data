# CoworkingView

Search coworking spaces and other flexible offices on [CoworkingView](https://coworkingview.com) from a Dify agent, chatflow, or workflow.

**Author:** coworkingview
**Version:** 0.0.1
**Type:** tool
**Source repository:** https://github.com/coworkingview/flex-office-data
**Homepage:** https://coworkingview.com
**Contact:** info@coworkingview.com

Maintained by [CoworkingView](https://coworkingview.com). This plugin was built with AI assistance.

## Description

The plugin reads the public CoworkingView API (`https://api.coworkingview.com`), the same catalogue used by the Python, R, and Rust clients in the source repository. It has three tools:

| Tool | What it does |
|---|---|
| Search workspaces | List flexible workspaces in one city, optionally limited to one workspace type |
| Get workspace | Open one listing by its slug |
| List cities | List the city slugs the catalogue supports |

Every workspace result includes the name, city, address, type, and the listing URL on `https://coworkingview.com` (no `www`). A field the API did not send is null. The plugin does not invent prices, addresses, or product types.

Search results do not include a street address, because that endpoint does not publish one. `address` is null until you call Get workspace. On a search, `type` is only the product you filtered by, or null when you did not filter. On a listing, `type` is the product codes published on that listing.

## Setup

No account, API key, or other credential is required. Install the plugin and use the tools. There is no authentication step.

The plugin labels are English. The Dify plugin schema's label object supports `en_US` (and `zh_Hans`, `ja_JP`, `pt_BR`). It does not have `de_DE` or `es_ES` fields. Pass the `locale` parameter `en`, `de`, or `es` when you want names and listing URLs in English, German, or Spanish.

## Connection

The tools call only `https://api.coworkingview.com` over HTTPS. The host is fixed. A request times out after 20 seconds. On HTTP 429 or a 5xx response the plugin waits at most 10 seconds and retries once.

The API allows 120 requests per minute per IP address. Search returns one page of at most 20 listings and does not walk further pages. Please do not use it to copy the catalogue.

`COWORKINGVIEW_API_URL` can point the process at another origin for a private mirror of this same API. Tool arguments cannot change the host.

## Usage

Call List cities first when you do not already know the city slug.

**List cities**

- `locale`: `en` (default), `de`, or `es`
- `country`: optional ISO code, such as `DE`

Use the returned `slug` as `city` below. `property_count` is the figure the API sent.

**Search workspaces**

- `city` (required): `berlin`, `madrid`, `abu-dhabi`, or another slug from List cities. `Berlin` is normalised to `berlin`.
- `workspace_type` (optional): `flex_desk`, `fix_desk`, `private_office`, `exclusive_bereich`, `day_pass`, `meeting_room`, `event_space`, `virtual_office`, or `membership`
- `locale`: `en`, `de`, or `es`
- `limit`: 1 to 20, default 10

Example: city `berlin`, workspace type `meeting_room`.

A result looks like:

```json
{
  "name": "St. Oberholz Coworking Berlin Mitte – Rosenthaler Straße",
  "city": "Berlin",
  "address": null,
  "type": ["meeting_room"],
  "url": "https://coworkingview.com/en/workspace/sankt-oberholz-rosenthaler-berlin",
  "slug": "sankt-oberholz-rosenthaler-berlin"
}
```

**Get workspace**

Pass `slug` from the search result. The same call with locale `de` uses the German listing path (`/de/buero/...`); locale `es` uses `/es/oficina/...`. When the API sends `webUrl`, that URL is used, with any `www` host rewritten to `coworkingview.com`.

```json
{
  "name": "St. Oberholz Coworking Berlin Mitte – Rosenthaler Straße",
  "city": "Berlin",
  "address": "Rosenthaler Straße 72a, 10119 Berlin, Germany",
  "type": ["flex_desk", "fix_desk", "private_office", "meeting_room", "virtual_office"],
  "url": "https://coworkingview.com/en/workspace/sankt-oberholz-rosenthaler-berlin",
  "slug": "sankt-oberholz-rosenthaler-berlin"
}
```

If `address` or `type` is null, say that the API did not provide it. Do not fill in a price. Published prices stay on the listing page.

Show `citation` and `notice` when they are present. Catalogue names and links are for search and reference. Descriptions, photos, and logos belong to the operators and are not returned.

## Development

From `integrations/dify/coworkingview`:

```bash
python3 -m unittest discover -s tests -t . -v
```

The tests use mocked API responses and do not call the network. Package with the Dify plugin CLI:

```bash
dify plugin package ./coworkingview -o coworkingview-0.0.1.difypkg
```

Run that command from the parent directory (`integrations/dify`). See `integrations/dify/PUBLISHING.md` for the Marketplace path and pull-request text.
