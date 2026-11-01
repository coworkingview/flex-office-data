# coworkingview

[![OCaml](https://img.shields.io/badge/ocaml-4.14%2B-orange.svg)](https://github.com/coworkingview/flex-office-data/tree/main/clients/ocaml)
[![Code: MIT](https://img.shields.io/badge/code-MIT-blue.svg)](https://github.com/coworkingview/flex-office-data/blob/main/clients/ocaml/LICENSE)
[![Data: CC BY 4.0](https://img.shields.io/badge/data-CC%20BY%204.0-lightgrey.svg)](https://creativecommons.org/licenses/by/4.0/)

OCaml client for the public API of [CoworkingView](https://coworkingview.com).

It gives you:

- **The CoworkingView Price Index** (`GET /v1/market/rates`): median, 25th and 75th percentile by city, with the sample size next to every figure. Open data under **CC BY 4.0**. The attribution string comes back on every result and has to travel with the figures.
- **Catalogue search** (`GET /v1/properties`): coworking spaces and other flexible offices, filtered by city, neighbourhood, operator, product, capacity and price.

No API key. Nothing is downloaded when the library is loaded. The default HTTP stack is `cohttp-lwt-unix`; JSON is `yojson`.

Maintained by [CoworkingView](https://coworkingview.com). This library was built with AI assistance.

## Install

Once the package is in opam-repository:

```bash
opam install coworkingview
```

Until that release is published, build it from this directory:

```bash
opam install . --deps-only --with-test --with-doc
dune build
```

`opam pin` of the monorepo needs the package subdirectory (`--subpath clients/ocaml` on opam 2.2 or newer). The opam-repository archive is a tarball of this directory alone, so `dune-project` sits at its root. See [OPAM-CHECKLIST.md](../../docs/OPAM-CHECKLIST.md).

## Usage

```ocaml
let () =
  Lwt_main.run
  @@
  let open Lwt.Syntax in
  let client = Coworkingview.make () in
  let* rates = Coworkingview.market_rates client ~city:"berlin" () in
  List.iter
    (fun (city : Coworkingview.city_rates) ->
      List.iter
        (fun (figure : Coworkingview.figure) ->
          Printf.printf "%s  %s  median %.0f %s  (n=%d)\n" city.city.name
            figure.option_type figure.median.amount figure.median.currency
            figure.sample_size)
        city.figures)
    rates.cities;
  print_endline rates.attribution;
  let* page = Coworkingview.properties client ~city:"berlin" ~page_size:10 () in
  Printf.printf "%d of %d spaces\n"
    (List.length page.properties)
    page.pagination.total;
  Lwt.return_unit
```

`Coworkingview.make ()` talks to `https://api.coworkingview.com`. Pass `~base_url` to point elsewhere, or set `COWORKINGVIEW_API_URL`. A trailing slash is removed. The default user agent is `coworkingview-ocaml/0.1.0 (+https://github.com/coworkingview/flex-office-data)`.

`locale` defaults to `En` and is always sent. The API requires one of `en`, `de` or `es`. `country` is a slug such as `"germany"`, matching `^[a-z0-9-]+$`.

### Price Index

```ocaml
Coworkingview.market_rates client ~city:"berlin" ~currency:Coworkingview.Eur ()
```

Optional filters are `city`, `country` and `currency` (`Eur`, `Gbp`, `Usd`, `Chf`, `Ves`, `Aed`). The result carries `attribution`, `license`, `license_url`, `as_of` and `scope`. A city always has `figures`, `by_type`, the entry-price fields and `buildings`. `day_pass`, `meeting_room`, `min` and `max` are present only when the API sends them.

### Catalogue

```ocaml
Coworkingview.properties client ~city:"berlin" ~product:Coworkingview.Flex_desk
  ~sort:Coworkingview.Price_asc ~page:1 ~page_size:50 ()
```

`page` starts at 1. `page_size` defaults to 50, which is the maximum the API accepts. `operator_slug` is sent as the `operator` query parameter. `sort` is `Random` (the API default when omitted), `Date_desc`, `Date_asc`, `Distance` or `Price_asc`. When the first page of a `random` sort returns a `seed`, pass it back on the following pages.

`Coworkingview.all_properties` follows pages until `limit` listings are collected (default 50, maximum 200) or the catalogue runs out. Each request asks for at most 50 rows. The seed from page 1 is forwarded. Photos, logos and the listing excerpt are not decoded.

### Errors

Failures raise `Coworkingview.Error`. `status` is the HTTP status, or `0` when no response arrived. `code` is the API code, or `HTTP_<status>`, `BAD_RESPONSE`, `TIMEOUT`, `CONNECTION` or `INVALID_ARGUMENT`. On HTTP 429 or 5xx the client waits `Retry-After` seconds, otherwise `RateLimit-Reset`, otherwise 2 seconds, at most 10, and tries once more. The per-request timeout is 20 seconds.

## Tests

```bash
dune runtest
dune build @doc
opam lint
```

The tests replay recorded responses from `test/fixtures/` and do not open a socket. Inject `~transport` and `~sleep` on `Coworkingview.make` to do the same in your own tests.

## Licence and attribution

- **Code:** MIT, see [LICENSE](LICENSE).
- **Price Index data:** [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Credit *CoworkingView Price Index* with a link to <https://coworkingview.com/en/tools/price-index>. Use the `attribution` field on the result.
- **Catalogue:** names, prices and links are for search and reference. Descriptions, photos and logos belong to the operators and are not included. A search that follows pages stops at 200 listings.

Changes are in [CHANGES.md](CHANGES.md). Issues: <https://github.com/coworkingview/flex-office-data/issues>.
