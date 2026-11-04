# Kimai Marketplace listing

Files in this directory are the ones a pull request to [kimai/www.kimai.org](https://github.com/kimai/www.kimai.org) would add for CoworkingView Workplace. They are not a pull request. Paths are relative to that repository.

Do not add both store wrappers. They have the same body. Pick one:

| File here | Add it as | When |
|---|---|---|
| `collections/_store/coworkingview-workplace.md` | `collections/_store/coworkingview-workplace.md` | This matches every plugin page on `main`, including the LeadMetrix listing merged on 2 October 2026 and the Invoice Payment Reminder listing merged in September 2026. A page with no `lang` in the front matter is expanded to every locale. |
| `collections/_store/en/coworkingview-workplace.md` | `collections/_store/en/coworkingview-workplace.md` | This is the path in the current store guide, `collections/_documentation/developer/store.md`. The directory name sets `lang` to `en`, so the page is English only. No listing on `main` lives under `collections/_store/en/` today. |

The other files are the same either way:

| File here | Add it as |
|---|---|
| `_data/developer.yml` | Append the `coworkingview` entry to `_data/developer.yml` |
| `_data/store/coworkingview-workplace.yml` | `_data/store/coworkingview-workplace.yml` |
| `_data/en/store.yml` | Merge the `items` entry into `_data/en/store.yml` |
| `_includes/store/coworkingview-workplace.md` | `_includes/store/coworkingview-workplace.md` |
| `_includes/store/changelog/CoworkingViewBundle.md` | `_includes/store/changelog/CoworkingViewBundle.md` |
| `_data/store/releases/CoworkingViewBundle.yaml` | `_data/store/releases/CoworkingViewBundle.yaml` |

There is no screenshot. New screenshots have to be WebP files under `images/marketplace/`, registered in `_data/screenshots.yml`, and captioned in `_data/en/store.yml`. English is the only locale this set covers. The guide says that is enough, and that you should say so in the pull request if you are not adding the other locales.

## What the store checked on 4 November 2026

Sources: `AGENTS.md`, `collections/_documentation/developer/store.md` (the page the site publishes as the store guide), `_layouts/store-item.html`, `_plugins/multi_language_collection.rb`, `_plugins/collection_path_lang.rb`, `_data/developer.yml`, and the plugin pages under `collections/_store/`. There is no `CONTRIBUTING` file in kimai/www.kimai.org. The README of that repository describes the Jekyll site and does not add listing rules.

Slug `coworkingview-workplace` keeps the developer id as a prefix, which the guide asks for. `title` and `intro` are only in `_data/en/store.yml`. The wrapper front matter is `title` and `type: plugin`. `price: 0` is the free badge. `changelog: true` needs the changelog include, or the site build fails when it tries to include a missing file. Compatibility is `_data/store/releases/CoworkingViewBundle.yaml` (`[plugin version, minimum Kimai version]`). The old `bundle.versions` key is not used.

`bundle.clone` is omitted. The install tab runs `git clone <url> CoworkingViewBundle` inside `var/plugins/`, so the repository root has to be the bundle. This plugin is the `kimai-plugin/` directory of coworkingview/flex-office-data, not the root of that repository. `github` points at the repository. With `price: 0` and no separate download URL, the button links to that repository's releases page, where the `kimai-v*` release attaches `CoworkingViewBundle-<version>.zip`.

### Dedicated repository

The store guide does not say the plugin has to live in its own repository. A listing can point `github` at any public repository, and the ZIP install instructions only require that the archive contain `CoworkingViewBundle/CoworkingViewBundle.php`.

The clone install does require a dedicated repository: the clone URL is checked out as `var/plugins/CoworkingViewBundle`, so the bundle class has to be at the root of that repository. Recent free plugins that offer clone, such as District09's personal calendar preference, use a repository whose root is the bundle. This listing does not offer clone, because a clone of flex-office-data would not.

Kimai's own application repository says, in its `AGENTS.md`, that each directory under `var/plugins/` is a separate plugin and its own Git repository. That rule is about not committing plugins into kimai/kimai. It is not a rule of the store.

### AI-assisted submissions

Allowed. `AGENTS.md` in kimai/www.kimai.org tells AI coding agents they may change the whole website, including store content. It does not forbid an AI-assisted listing. The store guide does not mention AI. The site owner reviews the pull request. There is no `CONTRIBUTING` file that adds another restriction.

The Kimai application repository has a different `AGENTS.md`. That file says agents must not create commits unless asked, and that work in `var/plugins/` is out of scope. It governs kimai/kimai, not a store pull request.

### Review, from the store guide

Send a pull request and wait. If there is no feedback in two weeks, you can ping. They install the plugin on the latest Kimai. The check is a compatibility test, not a full QA pass. They want the plugin to use the normal Kimai screens.

They look at:

- `composer.json` name, description, version, and homepage, as shown on System → Plugins
- an English translation file
- install steps that match the usual plugin layout (`var/plugins/CoworkingViewBundle/CoworkingViewBundle.php`, then a cache rebuild)
- documentation of what the plugin does and of any extra setup
- a support contact (the developer entry has `info@coworkingview.com`)

If the plugin is not public, they ask for a ZIP by email or a license key. This plugin is in a public repository, so that does not apply. Do not send that email as part of preparing the listing.

Screenshots are part of what they expect the documentation to show. This set does not include any. A later pull request can add WebP files. Do not invent figures, and do not put prices in the listing. The Price Index link is the public page only.
