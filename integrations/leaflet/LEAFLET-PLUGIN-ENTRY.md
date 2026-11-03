# Leaflet plugins-list entry

Do not open a pull request against Leaflet/Leaflet from this repository. The block below is the file to add there.

Checked against Leaflet `main` on 2026-11-03:

- `PLUGIN-GUIDE.md` (Adding to the plugins list): copy `docs/_plugins/template.md` into a category folder and set `compatible-v1` and `compatible-v2`.
- `CONTRIBUTING.md`: the plugins page is part of `docs/`. The site builder is `build/site.js`. It says front-matter values are strings, so the table compares `compatible-v1` with `"true"`.
- `docs/_plugins/template.md` fields: `name`, `category`, `repo`, `author`, `author-url`, `demo`, `compatible-v0`, `compatible-v1`, `compatible-v2`.
- `docs/_includes/plugin_category_table.html`: category `data-providers`, repo link, description body, V1/V2 checkmarks, a Demo link only when `demo` is non-blank, maintainer link from `author-url`.
- Merged plugin PRs used as the current shape: [#10514](https://github.com/Leaflet/Leaflet/pull/10514) (`docs/_plugins/mouse-coordinates/location-picker.md`), [#10328](https://github.com/Leaflet/Leaflet/pull/10328) (`docs/_plugins/synthetic-overlays/leaflet-india-boundary.md`), [#10388](https://github.com/Leaflet/Leaflet/pull/10388) (`docs/_plugins/synthetic-overlays/leaflet-daynight.md`). Each uses the front matter below, with `compatible-v0` empty, `compatible-v1: true`, and `compatible-v2: false`.

`template.md` labels `demo` as required, and PLUGIN-GUIDE calls a hosted demo essential (GitHub Pages is the suggested host). The table template still renders when `demo` is empty: the Demo cell is blank. This repo has a local demo at `integrations/leaflet/index.html` and no public demo URL. GitHub Pages was not enabled. The `demo` field is therefore empty. A Leaflet maintainer may ask for a URL before listing the plugin.

## File path

`docs/_plugins/data-providers/leaflet-coworkingview.md`

## File content

```markdown
---
name: leaflet-coworkingview
category: data-providers
repo: https://github.com/coworkingview/flex-office-data/tree/main/integrations/leaflet
author: CoworkingView
author-url: https://coworkingview.com
demo:
compatible-v0:
compatible-v1: true
compatible-v2: false
---

Leaflet layer that loads the CoworkingView Price Index (`GET /v1/market/rates`) and adds one marker per city with the median price. CC BY 4.0.
```

## Pull request

Title:

```text
Add leaflet-coworkingview to the data-providers plugins list
```

Body:

```markdown
Adds `docs/_plugins/data-providers/leaflet-coworkingview.md` for the Leaflet data-providers category.

The plugin is `L.coworkingView.layer()`, maintained in the CoworkingView flex-office-data repository. It loads the public CoworkingView Price Index and draws one marker per city with the median. The Price Index is CC BY 4.0.

Affiliation: this plugin and the Price Index are published by CoworkingView (https://coworkingview.com).

AI assistance: this submission was prepared with AI assistance.

`docs/_plugins/template.md` marks `demo` as required. There is no hosted demo URL (GitHub Pages is not enabled for this repo). A local demo is `index.html` in the plugin directory, so `demo` is left empty. `docs/_includes/plugin_category_table.html` omits the Demo link when that field is blank. `compatible-v1` is true (Leaflet 1.9) and `compatible-v2` is false.
```
