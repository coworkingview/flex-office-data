# Fedora package for cwv, the command-line client in the coworkingview
# crate. Source0 is the crates.io tarball. Source1 is vendor.tar.zst
# (Cargo.lock, .cargo/config.toml, vendor/), produced by
# integrations/copr/vendor.sh. The config replaces crates.io with the
# vendored tree, so the build does not use %%cargo_prep.

%global crate coworkingview

Name:           cwv
Version:        0.1.0
Release:        1%{?dist}
Summary:        Command-line client for the CoworkingView Price Index
# The crate's license is MIT. The Price Index figures the program prints
# are not shipped in this package.
License:        MIT
URL:            https://coworkingview.com/en/tools/price-index
Source0:        https://static.crates.io/crates/%{crate}/%{crate}-%{version}.crate
Source1:        vendor.tar.zst

BuildRequires:  cargo-rpm-macros
BuildRequires:  cargo
BuildRequires:  rust >= 1.88
# ring (via rustls) compiles C.
BuildRequires:  gcc
BuildRequires:  make
# %%autosetup unpacks Source1 (.tar.zst).
BuildRequires:  zstd

# ring 0.17 supports aarch64, arm, x86, and x86_64. %%{rust_arches} also
# lists ppc64le, s390x, and riscv64, which this crate cannot compile for.
# armv7hl is not a current COPR chroot. Ship x86_64 and aarch64.
ExclusiveArch:  x86_64 aarch64

%description
cwv is the command-line client for the CoworkingView Price Index:
median, 25th and 75th percentile prices for flexible office space,
city by city, and a search across shared offices, private offices,
meeting rooms, event spaces and virtual offices. It reads a public
API and needs no account.

The program is MIT. The Price Index figures it prints are CC BY 4.0.
Listings of individual spaces belong to their operators.

%prep
%autosetup -n coworkingview-%{version} -p1 -a1

%build
# The crate's release profile strips the binary. Keep the symbols so
# find-debuginfo can record a build-id. Fedora ends the build without one.
export CARGO_PROFILE_RELEASE_STRIP=none
export CARGO_PROFILE_RELEASE_DEBUG=2
export RUSTFLAGS="-C link-arg=-Wl,--build-id=sha1"
cargo build --offline --release
mkdir -p completions
./target/release/cwv completions bash > completions/cwv
./target/release/cwv completions zsh > completions/_cwv
./target/release/cwv completions fish > completions/cwv.fish
./target/release/cwv man > cwv.1

%install
install -D -m 0755 target/release/cwv %{buildroot}%{_bindir}/cwv
install -D -m 0644 cwv.1 %{buildroot}%{_mandir}/man1/cwv.1
install -D -m 0644 completions/cwv %{buildroot}%{_datadir}/bash-completion/completions/cwv
install -D -m 0644 completions/_cwv %{buildroot}%{_datadir}/zsh/site-functions/_cwv
install -D -m 0644 completions/cwv.fish %{buildroot}%{_datadir}/fish/vendor_completions.d/cwv.fish

%check
# Offline. The crates.io tarball ships the library and binary unit tests
# and the doctests. The fixture suites under tests/ live only in git.
cargo test --offline

%files
%license LICENSE
%doc README.md CHANGELOG.md
%{_bindir}/cwv
%{_mandir}/man1/cwv.1*
%{_datadir}/bash-completion/completions/cwv
# Own the completion directories. On openSUSE nothing else owns them,
# and an unowned directory fails the build. On Fedora, filesystem owns
# the same paths with mode 0755; sharing them with %%dir matches that.
%dir %{_datadir}/zsh
%dir %{_datadir}/zsh/site-functions
%{_datadir}/zsh/site-functions/_cwv
%dir %{_datadir}/fish
%dir %{_datadir}/fish/vendor_completions.d
%{_datadir}/fish/vendor_completions.d/cwv.fish

%changelog
* Wed Nov 04 2026 CoworkingView <info@coworkingview.com> - 0.1.0-1
- Initial package of cwv 0.1.0, the command-line client for the
  CoworkingView Price Index and coworking catalogue search
