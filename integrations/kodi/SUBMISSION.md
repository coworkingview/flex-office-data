# Submitting script.coworkingview to xbmc/repo-scripts

Do not open this pull request until a Kodi forum thread exists if you want the usual review questions already answered. The add-on checker does not require a forum URL, and a missing or failing forum link is a warning, so `addon.xml` omits `<forum>`.

## Target branch

`piers` on https://github.com/xbmc/repo-scripts

Kodi 22 "Piers" RC1 was released on 10 October 2026. The add-on rules say that once the first release candidate of a new Kodi is out, the previous repository accepts fixes and updates only, not new add-ons. New script submissions therefore go to `piers`, not `omega`. The wiki table that still lists Omega as accepting new add-ons has not caught up with that rule. Recent script pull requests merged after the RC (for example script.game.manuals 0.2.3, script.skinshortcuts v3.0.5, service.sendspin 1.0.2) target `piers`.

`xbmc.python` is `3.0.1`, which is the version kodi-addon-checker advises for `piers`. Any other value is a warning. The same number is what the checker advises for Omega, so the add-on also runs on Kodi 21, but a new add-on is submitted to `piers` only.

## Folder to copy

Copy this directory to the root of a branch based on `xbmc/repo-scripts` `piers`:

`integrations/kodi/script.coworkingview/`

The folder name must stay `script.coworkingview`. Do not copy `SUBMISSION.md`, `tests/`, or this repository's GitHub workflow. The official repository wants the add-on source tree, one commit, not a zip. A zip is not committed here: the add-on rules disallow extra archives, and repo-scripts builds the installable zip itself.

For a manual install outside the official repository, the zip root must be the add-on folder:

```bash
cd integrations/kodi
zip -r script.coworkingview-1.0.0.zip script.coworkingview -x '*__pycache__*' -x '*.pyc'
```

## Commit

One commit. Message:

```text
[script.coworkingview] 1.0.0
```

## Pull request

Title:

```text
[script.coworkingview] 1.0.0
```

Body:

```markdown
### Description

New program add-on. It asks for a city and shows the current CoworkingView Price Index for that city (median flexible-desk, fixed-desk, private-office, day-pass and meeting-room prices, with sample size and the CC BY 4.0 attribution).

The only network call is `GET https://api.coworkingview.com/v1/market/rates`, the public Price Index endpoint. There is no login, no advertising, and no tracking. Pure Python, using Kodi's standard library only.

The submitter is affiliated with CoworkingView, the publisher of the API this add-on reads. The add-on was prepared with AI assistance.

### Checklist:

- [x] My code follows the [add-on rules](https://kodi.wiki/view/Add-on_rules) and piracy stance of this project.
- [x] I have read the [CONTRIBUTING](https://github.com/xbmc/repo-scripts/blob/piers/CONTRIBUTING.md) document
- [x] Each add-on submission should be a single commit with using the following style: [script.foo.bar] 1.0.0

Additional information :
- Submitting your add-on to this specific branch makes it available to any Kodi version equal or higher than the branch name with the applicable Kodi dependencies limits.
- add-on development wiki page.
- Kodi pydocs provide information about the Python API
- PEP8 codingstyle which is considered best practise but not mandatory.
- This add-on repository has automated code guideline check which could help you improve your coding. You can find the results of these check at Codacy. You can create your own account as well to continuously monitor your python coding before submitting to repo.
- Development questions can be asked in the add-on development section on the Kodi forum.

Addon name: CoworkingView
Addon ID: script.coworkingview
Version: 1.0.0
Kodi branch: piers
Source: https://github.com/coworkingview/flex-office-data/tree/main/integrations/kodi/script.coworkingview
License: MIT
```

## Checker

```bash
pip install kodi-addon-checker==0.0.36
kodi-addon-checker --branch=piers integrations/kodi/script.coworkingview
```

`<website>` is `https://coworkingview.com/en`. `https://coworkingview.com` answers 301 to `/en`, and the checker warns when a metadata URL redirects.
