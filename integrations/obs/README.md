# cwv on the openSUSE Build Service

RPM packaging for the `cwv` command (crate `coworkingview` 0.1.0, MIT).
The package name is the binary, `cwv`. It builds from the crate published
on crates.io, offline, with dependencies in `vendor.tar.zst`.

Project: `home:coworkingview`. Package: `cwv`.

This directory does not create an OBS account. `osc` reads credentials
from `~/.config/osc/oscrc` and nowhere else in this repo.

## Files

| File | Role |
|---|---|
| `cwv.spec` | RPM spec. `Source0` is the crates.io `.crate`. `Source1` is `vendor.tar.zst`. `%cargo_build`, `%cargo_install`, `%cargo_test`. |
| `_service` | `download_files` and `cargo_vendor`, both `mode="manual"`. |
| `cwv.changes` | `osc vc` changelog, CoworkingView \<info@coworkingview.com\>. |
| `cwv-rpmlintrc` | Filters for the debuginfo packages and for `Source1` having no URL. |
| `project-meta.xml` | Meta for `home:coworkingview`. |
| `package-meta.xml` | Meta for package `cwv`. |
| `vendor.sh` | Downloads the crate and builds `vendor.tar.zst` with `cargo vendor`. |
| `publish.sh` | Runs the `osc` steps below, non-interactively. |
| `ci-rpmbuild.sh` | What CI runs inside `opensuse/tumbleweed`. |

`vendor.tar.zst` is the vendored crates.io graph (rustls, ring, clap, and
the rest). It is committed to the OBS package and is not committed to git.
`.gitignore` ignores `*.crate` and `vendor.tar.zst` in this directory if
you generate them here.

## Repositories

`project-meta.xml` builds:

| Repository | Path | Architectures |
|---|---|---|
| `openSUSE_Tumbleweed` | `openSUSE:Tumbleweed` / `standard` | `x86_64`, `aarch64` |
| `16.0` | `openSUSE:Leap:16.0` / `standard` | `x86_64`, `aarch64` |

`16.0` is openSUSE Leap 16.0. The [OBS repository naming
rules](https://en.opensuse.org/OBS_repositories) name Leap repositories
`X.Y`. The name `openSUSE_Leap_16.0` is not used, because
software.opensuse.org keys off the official name. Leap 16.0 ships
`cargo-packaging` (from SLFO) and a Rust newer than the crate's
`rust-version` 1.88, so the Leap build is enabled.

Tumbleweed's `standard` repository publishes both `x86_64` and
`aarch64`, which is how application projects such as `editors` build
Rust packages for both.

## What the spec does

Follows [openSUSE:Packaging Rust Software](https://en.opensuse.org/openSUSE:Packaging_Rust_Software)
and the specs in `devel:languages:rust` / Factory (`%{cargo_build}`,
`%{cargo_install}`, `%{cargo_test}`, `BuildRequires: cargo-packaging`,
`ExclusiveArch: %{rust_tier1_arches}`).

`%prep` is `%autosetup -n coworkingview-%{version} -p1 -a1`. rpm's
`rpmuncompress` unpacks a `.crate` (it is a gzip tarball). `-a1` unpacks
`vendor.tar.zst` on top of it: `Cargo.lock`, `.cargo/config.toml`, and
`vendor/`. That is the layout `cargo_vendor` writes. `%cargo_build` and
`%cargo_test` pass `--offline`.

`%check` runs the unit tests and doctests shipped in the crate. Those
do not touch the network. The fixture suites under `rust/tests/` are
not in the `.crate`.

The crate's release profile sets `strip = true`. The spec exports
`CARGO_PROFILE_RELEASE_STRIP=none` and `CARGO_PROFILE_RELEASE_DEBUG=2`
so rpm can split debuginfo. `gcc` and `make` are build requirements
because rustls pulls in ring's C code.

The package installs `/usr/bin/cwv`, its man page (`cwv man`), and
bash, zsh, and fish completions.

## Vendor tarball

Two ways to produce it. Both respect `Cargo.lock` (`--locked` /
`respect-lockfile`) and do not update dependencies.

**cargo vendor** (what CI and `publish.sh` run; no OBS service needed):

```sh
integrations/obs/vendor.sh /tmp/cwv-sources
```

That writes `/tmp/cwv-sources/coworkingview-0.1.0.crate` (sha256
`d1f5b5cad9a1738c9a0048ec223989b3ed06bb27d6bd14f5176ee583c72b43b4`)
and `/tmp/cwv-sources/vendor.tar.zst`.

**obs-service-cargo** (package `obs-service-cargo`), after
`download_files` has fetched the crate into the working copy:

```sh
osc service manualrun
```

`_service` is `mode="manual"`, so the OBS server does not regenerate
the tarball on commit. You generate it once and `osc ci` stores it in
the package. `publish.sh` passes `--noservice` for the same reason.

## Publish from a Linux box

Install `osc`, `cargo`, `curl`, `zstd`, and GNU `tar`. Create your OBS
account yourself and write `~/.config/osc/oscrc` (user and password for
`https://api.opensuse.org`). The login has to be allowed to edit
`home:coworkingview`. The meta files name the maintainer
`coworkingview`.

From a checkout of this repository:

```sh
integrations/obs/vendor.sh /tmp/cwv-sources

osc meta prj -F integrations/obs/project-meta.xml home:coworkingview
osc meta pkg -F integrations/obs/package-meta.xml home:coworkingview cwv
osc co home:coworkingview cwv
cd cwv
cp /tmp/cwv-sources/coworkingview-0.1.0.crate /tmp/cwv-sources/vendor.tar.zst .
cp ../integrations/obs/cwv.spec ../integrations/obs/cwv.changes ../integrations/obs/cwv-rpmlintrc ../integrations/obs/_service .
# adjust the cp paths if you did not start from the repo root

osc add cwv.spec cwv.changes cwv-rpmlintrc _service vendor.tar.zst coworkingview-0.1.0.crate
osc ci --noservice -m "Add cwv 0.1.0, the CoworkingView Price Index command-line client."
```

`osc meta prj -F` replaces the whole project meta. Use it when
`home:coworkingview` should match `project-meta.xml`.

The same steps, including the vendor tarball, without prompts:

```sh
integrations/obs/publish.sh
```

`publish.sh` exits if `~/.config/osc/oscrc` is missing. It does not
print the file.

After OBS has published the repositories:

```sh
# Tumbleweed
sudo zypper addrepo --refresh \
  https://download.opensuse.org/repositories/home:/coworkingview/openSUSE_Tumbleweed/home:coworkingview.repo
sudo zypper install cwv

# Leap 16.0 (repository name 16.0)
sudo zypper addrepo --refresh \
  https://download.opensuse.org/repositories/home:/coworkingview/16.0/home:coworkingview.repo
sudo zypper install cwv
```

## CI

`.github/workflows/obs.yml` runs `ci-rpmbuild.sh` in
`opensuse/tumbleweed`: `vendor.sh`, `rpmbuild -ba`, `rpmlint`, then
installs the rpm and runs `cwv --version`.
