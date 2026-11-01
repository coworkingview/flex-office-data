# Publish the D client

The package in `clients/d/` is the root of a standalone repository, `github.com/coworkingview/coworkingview-d`. Copy this directory there. Do not register `flex-office-data`, and do not tag this monorepo `v0.1.0` for the D package.

Checked against the DUB registry docs and the recipes of `clickhoused` 0.1.2 and `minijinja-d` 1.0.0-alpha.1 on 2026-11-01. `https://code.dlang.org/packages/coworkingview` returned 404 that day, so the name was free. Check it again before registering.

## Copy

```bash
rsync -a --delete \
  --exclude '.dub' \
  --exclude 'coworkingview-test-library' \
  --exclude 'libcoworkingview.a' \
  --exclude 'coworkingview_example' \
  clients/d/ /path/to/coworkingview-d/
```

`/path/to/coworkingview-d` is a git repository whose root is that directory. `dub.json` has to sit at the root. The registry reads the recipe from the repository root, not from `clients/d` of this monorepo.

| File | Why it is at the root |
|---|---|
| `dub.json` | Package name `coworkingview`, description, `authors`, `copyright`, `license`, `homepage`, `version`, `targetType` `library`. No dub dependencies. |
| `source/` | The library. `import coworkingview` loads `source/coworkingview/package.d`. |
| `README.md`, `LICENSE`, `CHANGES.md` | Install docs, the MIT licence, and the 0.1.0 notes. |
| `fixtures/`, `golden/` | Offline `dub test` inputs. They are part of the package so the standalone repo still tests. |
| `examples/berlin/` | Subpackage `coworkingview:example`. |

Confirm the copy:

```bash
cd /path/to/coworkingview-d
dub build
dub test
dub build :example
```

`dub test` must pass without a network connection. Linking needs libcurl (`libcurl4-openssl-dev` on Debian and Ubuntu).

## Recipe

`dub.json` matches what the registry asks for before a package can be published:

- `name` is `coworkingview` (lowercase, the allowed pattern `[a-z0-9_-]+`).
- `description` is one sentence.
- `authors` is `["CoworkingView"]`.
- `copyright` is `Copyright © 2026, CoworkingView`.
- `license` is `MIT` (SPDX). `LICENSE` is the MIT text.
- `homepage` is `https://coworkingview.com`.
- `targetType` is `library`.
- `version` is `0.1.0`. The git tag must be `v0.1.0`. If the recipe version and the tag differ, the registry rejects that version.
- `toolchainRequirements.frontend` is `>=2.097`, which DMD 2.097+ and the matching LDC satisfy.
- There is no `dependencies` object. HTTP is `std.net.curl`. JSON is `std.json`.

The README links to <https://coworkingview.com> and <https://coworkingview.com/en/api>, and it says the library was built with AI assistance.

## Tag and register

On `github.com/coworkingview/coworkingview-d`, not on `flex-office-data`:

```bash
git tag v0.1.0
git push origin HEAD
git push origin v0.1.0
```

Register the GitHub repository at <https://code.dlang.org/> with the organization `coworkingview` and the project `coworkingview-d`. Registration only links the repository. The registry polls for SemVer tags (`v0.1.0`) about twice an hour and publishes `0.1.0` when the recipe version matches.

The default user agent is `coworkingview-d/0.1.0 (+https://github.com/coworkingview/flex-office-data)`.
