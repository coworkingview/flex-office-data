# opam-repository checklist for `coworkingview` 0.1.0

Prepared on 2026-11-01. The submission file is in this repository and has **not** been sent to [ocaml/opam-repository](https://github.com/ocaml/opam-repository). Checksums in that file are placeholders.

| Draft | Path |
|---|---|
| opam file to copy | [`clients/ocaml/opam-repository/packages/coworkingview/coworkingview.0.1.0/opam`](https://github.com/coworkingview/flex-office-data/blob/main/clients/ocaml/opam-repository/packages/coworkingview/coworkingview.0.1.0/opam) |
| Pull request title and body | [`clients/ocaml/opam-repository/PULL_REQUEST.md`](https://github.com/coworkingview/flex-office-data/blob/main/clients/ocaml/opam-repository/PULL_REQUEST.md) |
| Package that the archive must contain | [`clients/ocaml/`](https://github.com/coworkingview/flex-office-data/tree/main/clients/ocaml) |

The in-repository `clients/ocaml/coworkingview.opam` is what `opam install .` uses. It has no `url` section. The submission file is the same metadata, plus `url`, and without `name` or `version` (those come from the directory name in opam-repository).

## Sources read

- [CONTRIBUTING.md](https://github.com/ocaml/opam-repository/blob/master/CONTRIBUTING.md) (manual publish layout, `url` + sha256 and sha512, `dune-release` / `opam-publish`)
- [Governance policies 0–14](https://github.com/ocaml/opam-repository/blob/master/governance/policies/README.md)
- [Archiving and inclusion](https://github.com/ocaml/opam-repository/blob/master/governance/policies/archiving.md) (compiler cutoff, `x-maintenance-intent`)
- [opam manual](https://opam.ocaml.org/doc/Manual.html) (fields, version ordering)
- [ocaml/opam#4185](https://github.com/ocaml/opam/issues/4185) and [`opamHTTP.ml` on master](https://github.com/ocaml/opam/blob/master/src/repository/opamHTTP.ml) (`pull_url ?subpath:_`)
- [`opamRepository.ml`](https://github.com/ocaml/opam/blob/master/src/repository/opamRepository.ml) (`extract_archive` binds `_subpath` and extracts the whole archive)

## Model pull requests

Small new-package or new-release PRs merged 29–30 October 2026. Each has `maintainer`, `authors`, `license`, `homepage`, `bug-reports`, `dev-repo` as a `git+https` URL, lower bounds, `dune build -p name`, `["dune" "subst"] {dev}`, `x-maintenance-intent: ["(latest)"]`, and `url` with sha256 and sha512. None uses md5 or `extra-files`.

| PR | Merged | What we copied |
|---|---|---|
| [parseff 0.5.0 #31047](https://github.com/ocaml/opam-repository/pull/31047) | 2026-10-30 | dune-release `.tbz` on `releases/download`, both checksums, `x-maintenance-intent` |
| [parkour 0.1.1 #31017](https://github.com/ocaml/opam-repository/pull/31017) | 2026-10-29 | `releases/download/<tag>/<pkg>-<version>.tar.gz`, tags, no `x-commit-hash` required |
| [rhema 0.1.1 #31018](https://github.com/ocaml/opam-repository/pull/31018) | 2026-10-29 | `doc` is a real Markdown URL on GitHub, not an odoc site |
| [libmojave 1.0.0 #31046](https://github.com/ocaml/opam-repository/pull/31046) | 2026-10-29 | `archive/refs/tags/<version>.tar.gz` is acceptable when the repository root **is** the dune project |

`cohttp-lwt-unix` 6.3.0 is the monorepo comparison. Its [opam file](https://github.com/ocaml/opam-repository/blob/master/packages/cohttp-lwt-unix/cohttp-lwt-unix.6.3.0/opam) points at `https://github.com/mirage/ocaml-cohttp/releases/download/v6.3.0/cohttp-6.3.0.tbz`. That archive is a dune workspace (`dune-project` at the top). `dune build -p cohttp-lwt-unix` selects one package inside it. The automatic GitHub archive of an unrelated monorepo is a different shape.

## Monorepo subdirectory

`flex-office-data` is a monorepo. The dune project lives in `clients/ocaml/`, not at the repository root. A package in a subdirectory **can** be published. opam-repository does not require the Git repository root to be the package. It requires the **unpacked archive** to be a package opam can install, which means `dune-project` at the archive root and `<package>.install` where opam looks for it (`_build/default/<package>.install` under that root).

Three ways other packages do this:

1. **dune-release** (CONTRIBUTING's recommended path, used by parseff and cohttp). It builds a `.tbz` of the dune project and uploads it to a GitHub release. Running it here would try to tag a version such as `0.1.0` at the monorepo root. This repository already uses language-scoped tags (`rust-v*`), and the release tag for this package is `ocaml-v0.1.0`. dune-release also rewrites `%%VERSION%%` from that tag. We do not use it for 0.1.0.
2. **`dune build -p <name>` inside an archive whose root is already the package** (parkour, rhema, and this package). The build line does not `cd` and does not pass `--root`.
3. **`subpath` on `url.src`.** Git pins honour `--subpath` (the git backend receives it). The HTTP backend does not. On master as of 2026-11-01, `OpamHTTP.pull_url` is declared `?subpath:_` and never reads it, and `extract_archive` in `opamRepository.ml` discards `_subpath` while unpacking. [ocaml/opam#4185](https://github.com/ocaml/opam/issues/4185) describes this exact failure mode (install file stuck in a subdirectory) and was closed on 2026-10-24, but those two functions still ignore the subpath. An opam file with `subpath: "clients/ocaml"` on the automatic tag archive would still fail to install.

`dune build -p coworkingview` from the monorepo root does not see this package. `dune build --root clients/ocaml -p coworkingview @install` writes `clients/ocaml/_build/default/coworkingview.install`. opam reads the install file from the source root, so that build would compile and then fail at install. Copying the install file up in a `build:` step would also be a source-mutating command, which [policy 11](https://github.com/ocaml/opam-repository/blob/master/governance/policies/README.md) forbids.

**What we ship instead.** Tag `ocaml-v0.1.0`, then pack only this package:

```bash
git archive --format=tar.gz --prefix=coworkingview-0.1.0/ \
  ocaml-v0.1.0:clients/ocaml -o coworkingview-0.1.0.tar.gz
```

Upload that file as a release asset. `url.src` is:

```
https://github.com/coworkingview/flex-office-data/releases/download/ocaml-v0.1.0/coworkingview-0.1.0.tar.gz
```

That is a GitHub release tarball for tag `ocaml-v0.1.0`. It is **not**:

```
https://github.com/coworkingview/flex-office-data/archive/refs/tags/ocaml-v0.1.0.tar.gz
```

The second URL is the whole monorepo. Hashing it and submitting it would produce a package whose checksum is valid and whose install still fails. The placeholder checksums are 64 and 128 hex zeros so the file lints as syntactically valid sha256 and sha512. Replace them with `sha256sum` and `sha512sum` of `coworkingview-0.1.0.tar.gz`, and delete the comment at the top of the submission file, before opening the pull request.

`["dune" "subst"] {dev}` matches the model packages. It runs only for a dev pin. The dune project hardcodes `(version 0.1.0)` and contains no `%%VERSION%%` markers, so a tag named `ocaml-v0.1.0` does not rewrite the version. The opam version is `0.1.0`, not `ocaml-v0.1.0` and not `v0.1.0`.

## Fields

| Field | Value | Why it is this |
|---|---|---|
| `opam-version` | `"2.0"` | Same as the merged examples |
| `name`, `version` | omitted from the submission file | Directory `packages/coworkingview/coworkingview.0.1.0/` supplies both. CONTRIBUTING says to remove them |
| `synopsis` | `Client for the CoworkingView public API` | Capitalised, no trailing period (lint 47) |
| `description` | the two endpoints, no API key, CC BY 4.0, 200-row cap | States what a user installs |
| `maintainer` | `CoworkingView <info@coworkingview.com>` | Lint error 23 if missing. Human contact for [policy 14](https://github.com/ocaml/opam-repository/blob/master/governance/policies/README.md) |
| `authors` | same | Lint warning 25 if missing |
| `license` | `"MIT"` | SPDX. Warning 62 if it is not an SPDX id. Same licence as `clients/ocaml/LICENSE` |
| `tags` | `http`, `json`, `coworking` | Optional. Present in parkour and in `dune-project` |
| `homepage` | `https://coworkingview.com` | Required by this release. Warning 35 if missing |
| `doc` | GitHub README on `main` | A real document, the same kind of URL rhema uses. Warning if absent is not universal, but reviewers ask when it 404s |
| `bug-reports` | GitHub issues | Warning 36 if missing |
| `dev-repo` | `git+https://github.com/coworkingview/flex-office-data.git` | Must be a VCS URL. Warning 37 if missing, error 42 if it is a plain `https://` URL |
| `depends` | lower bounds only, `>=` | [Policy 5](https://github.com/ocaml/opam-repository/blob/master/governance/policies/README.md). `alcotest` is `with-test`, `odoc` is `with-doc` ([policy 9](https://github.com/ocaml/opam-repository/blob/master/governance/policies/README.md)) |
| `build` | `dune subst` `{dev}`, then `dune build -p name -j jobs @install @runtest {with-test} @doc {with-doc}` | Same command as parseff, parkour and rhema |
| `x-maintenance-intent` | `["(latest)"]` | [Archiving policy](https://github.com/ocaml/opam-repository/blob/master/governance/policies/archiving.md). Only this version is maintained |
| `url.src` | release asset above | Archive root is the package |
| `url.checksum` | sha256 and sha512 | [Policy 13](https://github.com/ocaml/opam-repository/blob/master/governance/policies/README.md) forbids md5 alone. Warning 59 if a `url` has no checksum. Error 71 if the two hashes disagree with each other once they are real |

`x-maintenance-intent` is not in `dune-project`. Dune's `maintenance_intent` stanza needs dune lang 3.18, and the package stays on dune `>= 3.8` so the bound matches the build we tested. opam-repository reads the opam file, not the stanza.

Bounds, and the feature that forces each one:

| Dependency | Bound | Reason |
|---|---|---|
| `ocaml` | `>= 4.14` | `In_channel` and the string helpers used by the tests and the client. Above the [compiler cutoff of 4.11](https://github.com/ocaml/opam-repository/blob/master/governance/policies/archiving.md) (set 2026-05-05) |
| `dune` | `>= 3.8` | `(lang dune 3.8)` |
| `yojson` | `>= 2.0.0` | `Yojson.Safe.from_string` and the `Int` / `Intlit` / `Float` constructors the parser accepts |
| `lwt` | `>= 5.7.0` | `Lwt_unix.with_timeout`, `Lwt_unix.sleep` |
| `uri` | `>= 4.2.0` | `Uri.with_query'`, `Uri.of_string` |
| `cohttp`, `cohttp-lwt`, `cohttp-lwt-unix` | `>= 5.3.0` | `Cohttp_lwt_unix.Client.get`, `Cohttp_lwt.Body.to_string`, `Cohttp.Header`, `Cohttp.Code` |
| `alcotest` | `with-test & >= 1.7.0` | test runner |
| `odoc` | `with-doc & >= 2.4.0` | `dune build @doc` |

No `=`, no `>`, no preventive `<`. ocamlformat is a development tool and is not a dependency.

The name `coworkingview` was unused in opam-repository on 2026-11-01 (`packages/coworkingview` returned 404). [Policy 7](https://github.com/ocaml/opam-repository/blob/master/governance/policies/README.md) asks new names to avoid an `ocaml-` prefix. [Policy 6](https://github.com/ocaml/opam-repository/blob/master/governance/policies/README.md) asks for `0.1.0`, not `v0.1.0`. [Policy 4](https://github.com/ocaml/opam-repository/blob/master/governance/policies/README.md) forbids a misleading name: this package is the client for that API, maintained by the operator of the API.

## Policies 0–14

| Policy | How this package meets it | Rejection risk |
|---|---|---|
| [0 Inclusion](https://github.com/ocaml/opam-repository/blob/master/governance/policies/archiving.md) | Installable on OCaml 4.14 and 5.3 (CI in this repository). Sources will be the release asset. `x-maintenance-intent` covers 0.1.0 | Submitting before the asset exists fails the source check. A 404 `doc` URL fails the link check |
| [1 Do not remove published versions](https://github.com/ocaml/opam-repository/blob/master/governance/policies/README.md) | First publication | Later edits must be a new version or a `-1` revision, not a changed archive |
| [2 Do not make a published version uninstallable](https://github.com/ocaml/opam-repository/blob/master/governance/policies/README.md) | Bounds are lower bounds, so a newer compatible dependency still solves | Tightening a bound after merge needs a revision and a reason |
| [3 Utility](https://github.com/ocaml/opam-repository/blob/master/governance/policies/README.md) | Typed client for two public endpoints, with errors, pagination and retries | A one-function wrapper would be too thin. This is a full client of the API surface it claims |
| [4 Names](https://github.com/ocaml/opam-repository/blob/master/governance/policies/README.md) | Unused name, same as the service | Squatting a name the publisher does not operate |
| [5 Constraints](https://github.com/ocaml/opam-repository/blob/master/governance/policies/README.md) | `>=` only | An upper bound on `dune` or `cohttp` "just in case" is a common review comment. We have none |
| [6 Version spelling](https://github.com/ocaml/opam-repository/blob/master/governance/policies/README.md) | opam version `0.1.0` | Putting the git tag `ocaml-v0.1.0` in the version field |
| [7 `ocaml` prefix](https://github.com/ocaml/opam-repository/blob/master/governance/policies/README.md) | Name is `coworkingview` | Renaming to `ocaml-coworkingview` |
| [8 Dev packages](https://github.com/ocaml/opam-repository/blob/master/governance/policies/README.md) | `url.src` is a release asset, not a branch | Pointing `url.src` at `git+https://...#main` |
| [9 Dependencies](https://github.com/ocaml/opam-repository/blob/master/governance/policies/README.md) | Test and doc tools are filtered. No ocamlformat, merlin, or opam-dune-lint in `depends` | Adding the linters as unconditional depends |
| [10 Binaries](https://github.com/ocaml/opam-repository/blob/master/governance/policies/README.md) | Source package | Shipping a prebuilt binary |
| [11 Immutable archive](https://github.com/ocaml/opam-repository/blob/master/governance/policies/README.md) | One archive, no `patches`, no `sed` in `build` | Replacing the asset after merge, or hashing the monorepo archive and then "fixing" install with a patch |
| [12 No extra-files](https://github.com/ocaml/opam-repository/blob/master/governance/policies/README.md) | No `files/` directory | Adding a patch under `files/` |
| [13 No md5](https://github.com/ocaml/opam-repository/blob/master/governance/policies/README.md) | sha256 and sha512 | md5 only, or a single weak hash |
| [14 A person, and labelled AI](https://github.com/ocaml/opam-repository/blob/master/governance/policies/README.md) | Maintainer email is a human contact. The draft title/body says the PR was prepared with AI assistance and names CoworkingView as the operator of the API | An unlabelled bot PR, a huge generated comment, or no address a reviewer can write to |

## Lint

Run from `clients/ocaml` with opam 2.2 or newer (2.5.2 was used while preparing this package):

```bash
opam lint coworkingview.opam \
  opam-repository/packages/coworkingview/coworkingview.0.1.0/opam
opam exec -- dune build @install @runtest @doc
opam exec -- opam-dune-lint
```

Do not pass `--check-upstream` until the tag and the asset exist. That flag fetches `url.src` and reports error 60 when the URL 404s, which it will until the release is published.

Codes this package is written to avoid:

| Code | Meaning |
|---|---|
| 23 | `maintainer` missing |
| 25 | `authors` missing |
| 35 | `homepage` missing |
| 36 | `bug-reports` missing |
| 37 | `dev-repo` missing |
| 42 | `dev-repo` is not a VCS URL |
| 47 | synopsis does not start with a capital, or it ends with a period |
| 59 | `url` without a checksum |
| 62 | `license` is not SPDX |
| 63 | `subpath` set while `available` does not require opam `> 2.1` — we do not set `subpath` |
| 71 | checksum list has duplicates or inconsistent hashes |

CI in this repository runs `opam lint` on both files (the job fails if lint prints anything), `dune build @install @runtest @doc` on OCaml 4.14 and 5.3, and `opam-dune-lint` on 5.3. `opam-dune-lint` 0.6 depends on `dune >= 3.10 & < 3.21`. If a future dune 3.21 is the only installable dune, that one step needs a newer opam-dune-lint; the package bound on dune stays `>= 3.8`.

Tests use the fixtures in `clients/ocaml/test/fixtures/` and a fake transport. opam-repository CI has no network access to `api.coworkingview.com`. A test that called the live API would fail the publication CI.

`doc` returns 404 until this repository's pull request is merged, because it points at `blob/main/clients/ocaml/README.md`. opam-repo-ci checks that `homepage` and `doc` answer. Confirm both with `curl -fsI` after the merge, then submit.

Windows and the less common architectures are not given an `available` filter or `x-ci-accept-failures` in advance. `cohttp-lwt-unix` brings its own constraints. If opam-repo-ci fails on a platform, add the skip from that log, with a one-line reason, in a follow-up. A preemptive skip is a review comment we can avoid.

## Remaining steps

1. Merge the flex-office-data pull request that adds `clients/ocaml`.
2. Confirm these URLs return HTTP 200:
   - `https://coworkingview.com`
   - `https://github.com/coworkingview/flex-office-data/blob/main/clients/ocaml/README.md`
3. Tag the merge commit `ocaml-v0.1.0` and push the tag. Do not move the tag later ([policy 11](https://github.com/ocaml/opam-repository/blob/master/governance/policies/README.md)).
4. Build the archive from that tag:

   ```bash
   git archive --format=tar.gz --prefix=coworkingview-0.1.0/ \
     ocaml-v0.1.0:clients/ocaml -o coworkingview-0.1.0.tar.gz
   sha256sum coworkingview-0.1.0.tar.gz
   sha512sum coworkingview-0.1.0.tar.gz
   ```

5. Create the GitHub release for tag `ocaml-v0.1.0` and upload `coworkingview-0.1.0.tar.gz` so the `releases/download` URL exists. `gh release create` does this. The automatic "source code" archive GitHub attaches is not the file to checksum.
6. Replace the two zero checksums in `packages/coworkingview/coworkingview.0.1.0/opam` and delete the placeholder comment.
7. From a checkout of a fork of ocaml/opam-repository, copy that file to `packages/coworkingview/coworkingview.0.1.0/opam`. Do not copy `PULL_REQUEST.md`, `files/`, or a patch.
8. Open the pull request with the title and body in `PULL_REQUEST.md`. That body discloses the AI assistance and the affiliation (CoworkingView operates the API and the client) and gives `info@coworkingview.com` as the human contact.
9. Answer review comments from that mailbox. Keep replies short. If opam-repo-ci is red, fix it with a metadata change or a new point release, not by replacing the asset.
