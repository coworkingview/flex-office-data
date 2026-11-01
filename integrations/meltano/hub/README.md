# Meltano Hub files for tap-coworkingview

Prepared for a pull request to [meltano/hub](https://github.com/meltano/hub). These files are not submitted.

| File here | Where it goes in the Hub repo |
|---|---|
| `_data/meltano/extractors/tap-coworkingview/coworkingview.yml` | same path |
| `_data/maintainers.yml` | merge the `coworkingview` key into `_data/maintainers.yml` |
| `coworkingview.png` | `static/assets/logos/extractors/coworkingview.png` |

The logo is the existing CoworkingView mark from this repository (`integrations/nextcloud/coworkingview/img/app.png`). When the Hub pull request is opened, set `logo_url` to `/assets/logos/extractors/coworkingview.png`, which is the path the Hub site serves. Until then `logo_url` points at `integrations/meltano/hub/coworkingview.png`.

Also add this line under `extractors` in `_data/default_variants.yml`:

```yaml
tap-coworkingview: coworkingview
```

Settings and capabilities come from `tap-coworkingview --about --format=json` (singer-sdk 0.54.9), including the SDK settings the tap advertises (`stream_maps`, schema flattening, batch, faker). `city` defaults to `berlin`. There is no API key.
