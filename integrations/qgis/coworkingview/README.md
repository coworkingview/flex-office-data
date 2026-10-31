# CoworkingView for QGIS

Load flexible workspaces from the public [CoworkingView](https://coworkingview.com) catalogue as a point layer in QGIS 3.22 or newer. Filter by city and workspace type, read the listing in the attribute table, and open it on coworkingview.com.

The plugin is Python only. QGIS already provides PyQt and the QGIS libraries. There is nothing to `pip install`.

## Install

QGIS 3.22 or newer (the package declares `qgisMaximumVersion=3.99`, so it is for QGIS 3).

1. Build or download `coworkingview.zip`. The zip contains one top-level folder, `coworkingview/`.
2. In QGIS: **Plugins → Manage and Install Plugins → Install from ZIP**.
3. Enable **CoworkingView**.

From a checkout of this repository you can install the folder itself. Copy `integrations/qgis/coworkingview/` to the QGIS profile plugins directory:

| System | Plugins directory |
|---|---|
| Linux | `~/.local/share/QGIS/QGIS3/profiles/default/python/plugins/` |
| macOS | `~/Library/Application Support/QGIS/QGIS3/profiles/default/python/plugins/` |
| Windows | `%APPDATA%\QGIS\QGIS3\profiles\default\python\plugins\` |

The copied folder must be named `coworkingview`. Restart QGIS or use Plugin Reloader, then enable the plugin.

## Use

Open **Vector → CoworkingView → Show workspaces**, or the toolbar button. A dock opens on the right.

1. Wait for the city list. It comes from the public places index (`GET /v1/geo/bootstrap`). Cities with no listed spaces are left out. If that request fails, the plugin uses the published cities from `GET /v1/market/rates` instead.
2. Choose a city. A city is required. The plugin does not download the whole catalogue.
3. Choose a workspace type, or leave **All types**. The types are the product codes the API accepts: flex desk, dedicated desk, private office, exclusive area, day pass, meeting room, event space, virtual office, and membership.
4. Click **Load spaces**.

The new layer replaces the previous CoworkingView layer. Its attribute fields are:

| Field | Contents |
|---|---|
| `name` | Workspace name |
| `city` | City name |
| `address` | Street address, when the space detail includes one |
| `type` | Workspace types on that listing, in the API's product order |
| `url` | `https://coworkingview.com/...` listing |

**Open on CoworkingView** does three things:

- The layer action of that name (attribute table, and the identify result) opens `url`.
- The dock button opens the one selected workspace.
- The same action is registered for a single selected feature on the layer.

Points use the coordinates on the listing (WGS 84). A listing with no usable coordinates is counted in the status line and left off the map. The dock shows the citation and catalogue notice returned with the search, and the same text is stored in the layer metadata.

The layer is a memory layer. It lasts for the QGIS session. Export it (for example to GeoPackage) if you need to keep it. Exporting is your copy of that search, not a feed of the catalogue.

Loading asks the API for one page of listings at a time (50 per page, `sortBy=date-desc`) and then once per workspace so the address and type can be filled in. A search stops at 200 workspaces, the same cap the other clients in this repository use. The public API allows 120 requests a minute, so a large city takes a while. Progress is shown in the dock. **Cancel** stops the load. The previous layer is left as it was when a load fails.

## Data

Figures come from the public, keyless API at `https://api.coworkingview.com`, the same source as the Python, R and command-line clients in this repository. No account is required.

The plugin does not store prices, photos, logos or descriptions. Names, the city, the address, the workspace type and the link to the listing are what the layer carries. The Price Index is separate and is not drawn on the map.

Set `COWORKINGVIEW_API_URL` only if you need a different base URL. The default is `https://api.coworkingview.com`. Nothing is requested when the plugin is imported. The city list is requested when you open the dock.

## Build the zip

From the repository root:

```console
python3 integrations/qgis/build.py
```

That writes `integrations/qgis/dist/coworkingview.zip` and checks the layout plugins.qgis.org expects: one `coworkingview/` folder, `metadata.txt`, `__init__.py`, `LICENSE`, `icon.png`, and no `__pycache__` or `.pyc` files.

## Licence

The plugin code is [GPL-2.0-or-later](LICENSE), which the QGIS plugin repository requires. The rest of this repository is MIT. Catalogue listings are not licensed for reuse by the API: you may link to them. The notice returned with each search is shown in the dock. The CoworkingView Price Index is [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/); this plugin does not load those figures.

Issues: <https://github.com/coworkingview/flex-office-data/issues>
