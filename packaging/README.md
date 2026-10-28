# Packaging `cwv`

Manifests for the distribution channels of the `cwv` CLI (the Rust crate in
[`../rust`](../rust)). Everything that only exists after a release — checksums,
download URLs — is marked `TODO(release)`; `grep -rn 'TODO(release)' packaging`
lists what to fill in.

## Release order

1. Bump `version` in `rust/Cargo.toml`, update `rust/CHANGELOG.md`, run the
   gates (`cargo fmt --check`, `cargo clippy --all-targets -- -D warnings`,
   `cargo test`, `cargo publish --dry-run`).
2. Tag `rust-v<version>` and push the tag. The release workflow attaches the
   binaries to the GitHub release, plus a `SHA256SUMS` file:
   - `cwv-<version>-x86_64-unknown-linux-musl.tar.gz` (static)
   - `cwv-<version>-aarch64-unknown-linux-musl.tar.gz` (static)
   - `cwv-<version>-aarch64-apple-darwin.tar.gz`, `…-x86_64-apple-darwin.tar.gz`
   - `cwv-<version>-x86_64-pc-windows-msvc.zip` (built with
     `RUSTFLAGS="-C target-feature=+crt-static"`, so no VC++ runtime is needed)
3. `cd rust && cargo publish` — crates.io is the source for `cargo install
   coworkingview` and for the AUR package.
4. Update the channels below with the new version and checksums.

## Channels

| Channel | Files | How it is released |
|---|---|---|
| crates.io | `rust/Cargo.toml` | `cargo publish` from `rust/` (step 3). |
| AUR | `aur/PKGBUILD`, `aur/.SRCINFO` | Builds from the crates.io `.crate` tarball with `cargo build --frozen --release`. In a clone of `ssh://aur@aur.archlinux.org/cwv.git`: copy `PKGBUILD`, run `updpkgsums`, `makepkg --printsrcinfo > .SRCINFO`, test with `makepkg -si` (or `extra-x86_64-build`), commit, push. |
| Chocolatey | `chocolatey/cwv.nuspec`, `chocolatey/tools/*` | Downloads the Windows zip from the GitHub release. Fill `checksum64` (and the same value in `VERIFICATION.txt`), then `choco pack` and `choco push cwv.<version>.nupkg --source https://push.chocolatey.org/`. New versions go through Chocolatey moderation. |
| Snap | `snap/snapcraft.yaml` | Builds from the git tag with the `rust` plugin, `strict` confinement, `network` plug. `snapcraft remote-build` (or `snapcraft` in LXD), then `snapcraft upload --release=stable coworkingview_<version>_amd64.snap` (and arm64). The store name is `coworkingview` (`cwv` is reserved): `sudo snap install coworkingview` exposes `coworkingview.cwv`, with an optional `sudo snap alias coworkingview.cwv cwv`. |
| Docker | `rust/Dockerfile` | `FROM scratch` image with the static binary. `docker buildx build --platform linux/amd64,linux/arm64 --build-arg VERSION=<version> -t coworkingview/cwv:<version> -t coworkingview/cwv:latest --push rust/` (Docker Hub, namespace `coworkingview`). |

The homepage is https://coworkingview.com wherever a manifest has one field for
it (AUR `url`, Chocolatey `projectUrl`, Snap `website`); the source repository
https://github.com/coworkingview/flex-office-data goes in the source, docs and
issue fields.

Licensing to state in every listing: the code is MIT; the Price Index data the
tool prints is CC BY 4.0; catalogue content belongs to the operators and is not
licensed.
