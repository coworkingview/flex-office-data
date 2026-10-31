# Publishing the CoworkingView plugin to the Dify Marketplace

The installable package is built from `integrations/dify/coworkingview` with the official Dify plugin CLI:

```bash
dify plugin package integrations/dify/coworkingview -o coworkingview-0.0.1.difypkg
dify plugin checksum coworkingview-0.0.1.difypkg
```

`dify plugin package` validates the manifest, provider, and tools before it writes the archive. The filename is `coworkingview-0.0.1.difypkg` (`name` + `version` from `manifest.yaml`).

## Where the package goes

Repository: https://github.com/langgenius/dify-plugins

Path, from the current Marketplace submission guide (`<author>/<plugin-name>/<plugin-package>.difypkg`):

```text
coworkingview/coworkingview/coworkingview-0.0.1.difypkg
```

Create that directory in a fork and add only this one file in the pull request. A pull request that changes more than one `.difypkg` is rejected. Do not put the package at the repository root, and do not commit the plugin source tree next to it. The source of truth for this version is https://github.com/coworkingview/flex-office-data (`integrations/dify/coworkingview`).

## Pull request template

Open the pull request against `langgenius/dify-plugins` `main`. Keep every section below. This plugin is maintained by CoworkingView and was built with AI assistance; that disclosure is part of the template text.

```markdown
# Plugin Submission

## Plugin information

- **Author**: coworkingview
- **Plugin name**: coworkingview
- **Version**: 0.0.1
- **Source repository**: https://github.com/coworkingview/flex-office-data
- **Contact**: info@coworkingview.com

## Submission type

- [x] New plugin
- [ ] Version update

## What changed

New tool plugin for the public CoworkingView catalogue (https://coworkingview.com). It searches flexible workspaces by city and workspace type, opens one listing, and lists supported cities. Results return the name, city, address, type, and the listing URL on https://coworkingview.com. The plugin does not invent prices or other fields the API omitted.

This plugin is maintained by CoworkingView (https://coworkingview.com, info@coworkingview.com). It was built with AI assistance. CoworkingView is responsible for the behaviour of the tools, the mapping onto the public API, and the tests.

## Risk level

- [ ] Low risk
- [x] Medium risk
- [ ] High risk

The plugin sends the city, workspace type, locale, limit, and listing slug supplied by the user or the model to one fixed host, https://api.coworkingview.com. It does not accept a URL, execute commands or code, run SQL, touch the filesystem, or automate a browser. Choose Medium because those search parameters leave the Dify workspace. They are not highly sensitive personal data, and there is no credential.

## Required checks

- [x] I have read and followed the [Marketplace submission requirements](https://github.com/langgenius/dify-plugins/blob/main/docs/plugin-submission-requirements.md).
- [x] I have read and comply with the [Plugin Development Guidelines](https://docs.dify.ai/en/develop-plugin/publishing/standards/contributor-covenant-code-of-conduct).
- [x] I tested this plugin on Dify Community Edition and Dify Cloud, or documented any limitation below.
- [x] The package contains only files needed at runtime.
- [x] The package does not contain secrets, local credentials, `.env` files, `.git` directories, virtual environments, caches, logs, or IDE files.
- [x] The package does not contain executables or bundled binaries, or I explained why they are required below.
- [x] The plugin README includes setup steps, usage instructions, required APIs or credentials, connection requirements, and the source repository link.
- [x] The plugin includes `PRIVACY.md` or a hosted privacy policy, and `manifest.yaml` references it.
- [x] All user-facing text is primarily in English, with any localized README files following the [i18n guidance](https://docs.dify.ai/en/develop-plugin/features-and-specs/plugin-types/multilingual-readme).

## Security and privacy notes

The plugin performs HTTPS GET requests with `urllib.request.urlopen` to the fixed origin `https://api.coworkingview.com` only (`/v1/properties`, `/v1/properties/{slug}`, `/v1/geo/bootstrap`). Tool arguments cannot change the host. `COWORKINGVIEW_API_URL` is a process environment override for a private mirror, not a tool parameter. Timeout is 20 seconds. HTTP 429 and 5xx are retried once, after a wait of at most 10 seconds.

No API key is required or stored. The plugin does not collect, store, or log personal data. It transmits the city, workspace type, locale, limit, country code, and listing slug to CoworkingView so the public catalogue can answer. Privacy policy: `PRIVACY.md`, and https://coworkingview.com/en/privacy.

No command execution, code execution, SQL, SSH, filesystem writes, or browser automation. Listing URLs returned to the model are `https://coworkingview.com/...` only.

## Local validation

Not installed against a live Dify Community Edition or Dify Cloud workspace in this change. Validation that did run:

- `python3 -m unittest discover -s tests -t . -v` in `integrations/dify/coworkingview` (mocked API responses; no live network).
- `dify plugin package` (Dify plugin CLI 0.6.13) and `dify plugin checksum`.
- `python3 validator/validate-difypkg.py coworkingview-0.0.1.difypkg` from langgenius/dify-marketplace-toolkit: exit 0, no blocking failures.

## Reviewer notes

Maintained by CoworkingView (https://coworkingview.com). Built with AI assistance; the maintainer is responsible for the submission. The icon is the official off-white serif "CV" mark with a gold dot (`https://coworkingview.com/icon-192.png`), not a red logo. Plugin labels are `en_US` only: the plugin `I18nObject` does not define `de_DE` or `es_ES`. Result language is the tool `locale` parameter (`en`, `de`, `es`).
```
