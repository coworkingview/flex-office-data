# cwv on Fedora COPR

RPM packaging for the `cwv` command (crate `coworkingview` 0.1.0, MIT).
The package name is the binary, `cwv`. It builds from the crate published
on crates.io, offline, with dependencies in `vendor.tar.zst`.

`vendor.tar.zst` is not committed. CI builds it, packs an SRPM, and
rebuilds that SRPM inside `fedora:latest`.

## Files

| File | Role |
|---|---|
| `cwv.spec` | RPM spec. `Source0` is the crates.io `.crate`. `Source1` is `vendor.tar.zst`. |
| `vendor.sh` | Downloads the crate and builds `vendor.tar.zst` with `cargo vendor`. |
| `ci-srpm.sh` | What CI runs inside `fedora:latest`: vendor, `rpmbuild -bs`, `rpmbuild --rebuild`. |

The spec does not use `%cargo_prep` or `cargo-packaging`. `%prep` is

```
%autosetup -n coworkingview-%{version} -p1 -a1
```

`rpmuncompress` unpacks the `.crate` (a gzip tarball). `-a1` unpacks
`vendor.tar.zst` on top of it: `Cargo.lock`, `.cargo/config.toml`, and
`vendor/`. The config replaces crates.io with that `vendor/` directory.
`%build` runs `cargo build --offline --release`. `%check` runs
`cargo test --offline`. The package installs `/usr/bin/cwv`, its man
page (`cwv man`), and bash, zsh, and fish completions.

`%files` owns `/usr/share/zsh`, `/usr/share/zsh/site-functions`,
`/usr/share/fish`, and `/usr/share/fish/vendor_completions.d`. On Fedora
the `filesystem` package owns those paths (mode 0755) and the ownership
is shared. On openSUSE nothing else owns them; the same `%dir` lines are
in `integrations/obs/cwv.spec`.

The crate's release profile sets `strip = true`. The spec turns that off
and passes `-C link-arg=-Wl,--build-id=sha1`, because Fedora rejects a
binary with no build-id. `gcc` and `make` are build requirements because
rustls pulls in ring's C code. The crate declares `rust-version` 1.88.

`%check` runs the unit tests and doctests shipped in the crate. Those do
not touch the network. The fixture suites under `rust/tests/` are not in
the `.crate`.

## Vendor tarball

```sh
integrations/copr/vendor.sh /tmp/cwv-sources
```

That writes `/tmp/cwv-sources/coworkingview-0.1.0.crate` (sha256
`d1f5b5cad9a1738c9a0048ec223989b3ed06bb27d6bd14f5176ee583c72b43b4`)
and `/tmp/cwv-sources/vendor.tar.zst`.

## Chroots

`ExclusiveArch` is `x86_64` and `aarch64`. ring 0.17, which rustls
pulls in, compiles on aarch64, arm, x86, and x86_64. It does not compile
on ppc64le, s390x, or riscv64, so those COPR chroots are excluded.
`armv7hl` is not a current COPR chroot.

Build the SRPM on the supported Fedora releases plus rawhide, both
architectures. Fedora 45 was released on 3 November 2026. Fedora 43 is
supported until four weeks after that. Fedora 42 is no longer a full
COPR target (only `fedora-42-riscv64` remains, and ring cannot build
there).

| Release | Chroots |
|---|---|
| Fedora 43 | `fedora-43-x86_64`, `fedora-43-aarch64` |
| Fedora 44 | `fedora-44-x86_64`, `fedora-44-aarch64` |
| Fedora 45 | `fedora-45-x86_64`, `fedora-45-aarch64` |
| Rawhide | `fedora-rawhide-x86_64`, `fedora-rawhide-aarch64` |

`fedora-eln-x86_64` and `fedora-eln-aarch64` match `ExclusiveArch` as
well. ELN tracks the next RHEL and is not a release to point users at.

A tag `copr-v*` runs `.github/workflows/copr-release.yml` in
`fedora:latest`: `vendor.sh`, `rpmbuild -bs`, `rpmbuild --rebuild`, then
attaches the `.src.rpm` to the GitHub Release for that tag. `%{?dist}`
stays in the spec stored in the SRPM, so each COPR chroot expands its
own dist tag. The SRPM filename carries the dist of `fedora:latest` at
the time the workflow ran.

Pull requests that touch `integrations/copr/` run the same rebuild.

Submit the SRPM from the release:

```sh
copr-cli build \
  --chroot fedora-43-x86_64 --chroot fedora-43-aarch64 \
  --chroot fedora-44-x86_64 --chroot fedora-44-aarch64 \
  --chroot fedora-45-x86_64 --chroot fedora-45-aarch64 \
  --chroot fedora-rawhide-x86_64 --chroot fedora-rawhide-aarch64 \
  OWNER/PROJECT cwv-*.src.rpm
```
