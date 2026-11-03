# Matplotlib third-party entry

Draft for [matplotlib/mpl-third-party](https://github.com/matplotlib/mpl-third-party), the list served at <https://matplotlib.org/mpl-third-party/>. This repository does not open that pull request.

Read on 2026-11-03 from the default branch `main`. There is no `CONTRIBUTING` file. The contribution rules are the root [README](https://github.com/matplotlib/mpl-third-party/blob/main/README.md), [package-schema.json](https://github.com/matplotlib/mpl-third-party/blob/main/package-schema.json), [section_names.yml](https://github.com/matplotlib/mpl-third-party/blob/main/section_names.yml), [.github/pull_request_template.md](https://github.com/matplotlib/mpl-third-party/blob/main/.github/pull_request_template.md), and the pre-commit hook that validates `packages/*.yml` with that schema (`.pre-commit-config.yaml`, `check-jsonschema`). `.yamllint.yml` extends the defaults, turns off `document-start`, and sets `line-length` to 88.

## What the listing expects

There is no `packages.yml`. An entry is one file in `packages/`. The schema requires `name`, `repo`, `section` and `description`. `description` must match `^.+\.$` (it has to end with a period). Optional fields are `site`, `keywords`, `pypi_name`, `conda_package`, `conda_channel` and `badges`. Unknown keys are rejected.

`repo` must be `owner/name` or an `https://` URL. `python/build.py` only keeps an `owner/name` value (it splits on a single slash and skips anything else), then links the code badge to `https://github.com/<repo>`. Use `coworkingview/flex-office-data`. A subdirectory URL is dropped by that script.

`section` must be a key of `section_names.yml` after lower-casing. The key `domain specific libraries` is rendered as **Domain-specific libraries**. That is the right section: the package draws Price Index bars for flexible-office rates. It does not add a general plot type.

`python/build.py` defaults `pypi_name` and `conda_package` to the GitHub repository name. That would be `flex-office-data`, which is not this distribution, so `pypi_name` has to be set to `mpl-coworkingview`.

The default badges are `pypi` and `conda`. The build requests `https://pypi.org/pypi/<pypi_name>/json` and drops the PyPI badge unless the status is 200. It requests `https://anaconda.org/<conda_channel>/<conda_package>/` and drops the conda badge unless that page exists. The root README also asks for the `Framework :: Matplotlib` classifier, which this package sets.

`site` is optional. The README's comment is "optional, default repo site" and its example is a documentation URL (`https://matplotlib.org/cmocean`). In `python/template.rst` the package name links to `site` when that badge is present, and to the GitHub repo otherwise. The inherited note in `python/README.md` calls `site` "the site that the documentation can be found at." It is the documentation link, not a homepage field. `https://coworkingview.com` is the product homepage (`project.urls.Homepage` only). The value below is the package documentation URL, the same URL as `project.urls.Documentation`.

Do not set `conda_package` or `conda_channel`. There is no conda package. Setting them would point the conda badge at a project that does not exist; the build would then remove the badge. Omitting both leaves the default lookup, which also misses, and the badge is removed the same way. That is the honest outcome until a conda-forge package exists.

The README says the YAML file name and the repository name should ideally match. This package lives in a monorepo, so name the file `packages/mpl-coworkingview.yml` (the distribution name, which is how the other `mpl-*` files are named) and mention the monorepo in the pull request.

## Publish before opening the Matplotlib pull request

The package has to be on PyPI or the PyPI badge is removed, and the documentation URL above has to resolve. Tag `mpl-v0.1.0` (annotated, tagger CoworkingView). `.github/workflows/mpl-release.yml` builds this directory and publishes with Trusted Publishing (`pypa/gh-action-pypi-publish`, GitHub environment `pypi`). Do not open the Matplotlib pull request until `https://pypi.org/pypi/mpl-coworkingview/json` returns 200. This repository does not push that tag and does not open the Matplotlib pull request.

## YAML

Add `packages/mpl-coworkingview.yml`:

```yaml
name: mpl-coworkingview
repo: coworkingview/flex-office-data
section: domain specific libraries
description: Bar charts of flexible-office prices from the CoworkingView Price Index.
site: "https://github.com/coworkingview/flex-office-data/tree/main/\
  integrations/matplotlib#readme"
keywords: [coworking, "price index", "flexible office"]
pypi_name: mpl-coworkingview
```

The `site` scalar is one URL. The backslash is YAML's double-quoted line break, so the line stays inside the 88-character yamllint limit. The loaded value is `https://github.com/coworkingview/flex-office-data/tree/main/integrations/matplotlib#readme`.

## Pull request

The Matplotlib pull request template is only the heading `## PR Summary`.

**Title:** Add mpl-coworkingview

**Body:**

```markdown
## PR Summary

Add `packages/mpl-coworkingview.yml` under Domain-specific libraries (`section: domain specific libraries`).

mpl-coworkingview draws Matplotlib bar charts of flexible-office medians from the CoworkingView Price Index (`GET /v1/market/rates`), with the CC BY 4.0 attribution on the chart. The distribution is on PyPI as `mpl-coworkingview` and declares the `Framework :: Matplotlib` classifier. Documentation is the README at the `site` URL.

`site` is that documentation URL. https://coworkingview.com is the product homepage, and this listing uses `site` as the documentation link, so the homepage is not the `site` value. `pypi_name` is set because the GitHub repository is the flex-office-data monorepo; the default would be `flex-office-data`. `conda_package` and `conda_channel` are omitted because there is no conda package. The YAML file is named after the distribution rather than the monorepo.

I work on CoworkingView and I am affiliated with the project. This pull request was prepared with AI assistance.
```
