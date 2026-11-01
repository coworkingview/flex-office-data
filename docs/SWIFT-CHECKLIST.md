# Publish the Swift client

The package in `clients/swift/` is the root of a standalone repository, `github.com/coworkingview/coworkingview-swift`. This file is the publish checklist. The same file is at `clients/swift/docs/SWIFT-CHECKLIST.md`, so it is still there after the copy.

Nothing in this repository was tagged, pushed to CocoaPods trunk, or submitted to the Swift Package Index. Do not send the trunk registration email until you are ready to publish. Trunk sends that email itself; this checklist does not.

Checked against the live docs on 2026-11-01.

## Copy `clients/swift` to the standalone repo

From a checkout of this repository:

```bash
rsync -a --delete \
  --exclude '.build' \
  --exclude '.swiftpm' \
  clients/swift/ /path/to/coworkingview-swift/
```

`/path/to/coworkingview-swift` is a new git repository whose **root** is that directory. After the copy these files sit at the root, which is what both indexes require:

| File | Why it is at the root |
|---|---|
| `Package.swift` | Swift Package Index and SwiftPM require it in the repository root. `swift-tools-version` is 5.9. |
| `CoworkingView.podspec` | `pod lib lint` / `pod trunk push` run from the repo root. The filename matches the pod name. |
| `.spi.yml` | SPIManifest reads this from the repository root. |
| `README.md`, `LICENSE`, `CHANGELOG.md` | Install docs, the MIT file CocoaPods checks, and the release notes. |
| `Sources/CoworkingView/` | The library target, including DocC comments and `CoworkingView.docc`. |
| `Tests/CoworkingViewTests/` | XCTest fixtures. No network. |

Confirm the copy before tagging:

```bash
cd /path/to/coworkingview-swift
swift test
swift package dump-package >/dev/null
pod lib lint
```

`swift package dump-package` must print valid JSON. That is one of the PackageList checks.

## Tag 0.1.0

The podspec source is `https://github.com/coworkingview/coworkingview-swift.git` at tag `0.1.0`. The tag has to be on the commit you are publishing, and the version in the podspec has to be `0.1.0`.

```bash
git tag 0.1.0
git push origin HEAD
git push origin 0.1.0
```

Do this on `github.com/coworkingview/coworkingview-swift`, not on `flex-office-data`.

`pod spec lint` clones that tag. It cannot pass before the tag is on GitHub. `pod lib lint` does not clone it; CI in this repository runs `pod lib lint`.

## CocoaPods trunk

Rules checked:

- [Podspec syntax reference v1.16.1](https://guides.cocoapods.org/syntax/podspec.html). Required attributes present: `name`, `version`, `summary`, `homepage`, `license`, `author`, `source`. `summary` is under 140 characters. `description` is longer than `summary` and is not the same string. `license` is `{ :type => 'MIT', :file => 'LICENSE' }`. `LICENSE` has no extension, which the linter allows (the other allowed extensions are `.txt`, `.md`, `.markdown`). `author` is `CoworkingView <info@coworkingview.com>` via `{ 'CoworkingView' => 'info@coworkingview.com' }`. `homepage` is `https://coworkingview.com`. `documentation_url` is `https://coworkingview.com/en/api`.
- `source` is `git: https://github.com/coworkingview/coworkingview-swift.git`, tag `0.1.0`. The linter warns unless the git URL is `https`, ends in `.git`, does not use `www`, and the tag string contains the version. `0.1.0` contains `0.1.0`.
- `swift_versions` is `['5.9', '6.0']`. Lint compiles with the newest listed version. Deployment targets are per platform, which is how one podspec supports more than one platform: iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0. Those match `Package.swift`.
- `source_files` is `Sources/CoworkingView/**/*.swift`. Tests and the DocC catalog are not part of the pod.
- There is no `prepare_command`. Since May 2025 trunk rejects **new** pods that set `prepare_command` ([CocoaPods Trunk Read-only Plan](https://blog.cocoapods.org/CocoaPods-Specs-Repo/), May 2025 update).
- [Specs and the Specs Repo](https://guides.cocoapods.org/making/specs-and-specs-repo.html): run `pod spec lint` and ship a semantic version. Trunk does not accept a spec that fails lint.
- [Making a CocoaPod](https://guides.cocoapods.org/making/making-a-cocoapod.html) and [Using Pod Lib Create](https://guides.cocoapods.org/making/using-pod-lib-create.html): `pod lib lint` checks the files on disk and does not use the network. `pod spec lint` checks the git tag. For a public pod, CocoaPods warnings fail the push. Xcode warnings do not. CI passes `--allow-warnings` so an Xcode warning does not fail the job. Before `pod trunk push`, run `pod lib lint` **without** `--allow-warnings` and fix any CocoaPods warning.
- [Getting setup with Trunk](https://guides.cocoapods.org/making/getting-setup-with-trunk.html):

```bash
pod trunk register info@coworkingview.com 'CoworkingView' --description='coworkingview-swift release'
pod trunk me
pod spec lint CoworkingView.podspec
pod trunk push CoworkingView.podspec
```

On 2026-11-01 `https://trunk.cocoapods.org/api/v1/pods/CoworkingView` returned 404, so the name was free. Check it again before pushing; trunk will reject a name that was taken in the meantime.

`pod trunk register` emails `info@coworkingview.com` a confirmation link. The session is per machine and has no password. Open the link, then `pod trunk me` should show the session. `pod trunk push` lints again and uploads the spec. The first push makes that account the owner of `CoworkingView`.

Trunk becomes read-only on **2026-12-02**. After that, no new pod and no new version is accepted. The same post schedules a read-only test during **2026-11-01 to 2026-11-07**, so a push in that week can be rejected even though the permanent date is 2 December. Existing pods keep installing after the switch. This pod still has to be pushed before 2026-12-02 if it is going to exist on trunk.

## Swift Package Index

Rules checked:

- [PackageList README](https://github.com/SwiftPackageIndex/PackageList/blob/main/README.md) and the [add-package form](https://github.com/SwiftPackageIndex/PackageList/issues/new?template=add_package.yml) as of 2026-11-01. The form asks for one repository URL per line. Requirements it states:
  - The repository is public.
  - `Package.swift` is in the root.
  - Swift 5.0 or later. This package is 5.9.
  - At least one product that other apps can depend on. The product is the `CoworkingView` library.
  - At least one semantic-version tag. Tag `0.1.0` first, then submit.
  - `swift package dump-package` prints valid JSON on the latest toolchain.
  - The URL includes the scheme and the `.git` suffix: `https://github.com/coworkingview/coworkingview-swift.git`.
  - The package compiles.
- Recent listings are one-line additions merged by the PackageList bot. Examples merged on 2026-06-25: [libpag/pag-ios](https://github.com/SwiftPackageIndex/PackageList/pull/14174), [OpenSpatial](https://github.com/SwiftPackageIndex/PackageList/pull/14170), [PaginatedRESTClient](https://github.com/SwiftPackageIndex/PackageList/pull/14166). Submit the form. Do not open a hand-written pull request against PackageList.
- [SPIManifest](https://swiftpackageindex.com/SwiftPackageIndex/SPIManifest/documentation/spimanifest/commonusecases) and the [manifest model](https://github.com/SwiftPackageIndex/SPIManifest/blob/main/Sources/SPIManifest/Manifest.swift). `version: 1` is required. `documentation_targets` is read only under `builder.configs`, not as a top-level key (a top-level key is ignored). `external_links.documentation` is the key for an existing documentation site. The manifest is rejected above 1500 bytes. `.spi.yml` in this package is:

```yaml
version: 1
builder:
  configs:
    - documentation_targets: [CoworkingView]
external_links:
  documentation: https://coworkingview.com/en/api
```

`documentation_targets: [CoworkingView]` asks SPI to build DocC for that target (symbol comments plus `CoworkingView.docc`). `external_links.documentation` points the package page at the HTTP API reference. SPI documents the two as separate setups; both keys are valid together and both are set so the generated docs and the API reference are declared.

After the package is indexed, the PackageList README says to add the shields.io badges from the "Do you maintain this package?" link on the package page. Those badges 404 until the package is in the index, so they are not in the README yet.

Form to submit, after the tag is public:

<https://github.com/SwiftPackageIndex/PackageList/issues/new?template=add_package.yml>

New Packages field:

```text
https://github.com/coworkingview/coworkingview-swift.git
```
