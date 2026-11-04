#
# spec file for package cwv
#
# Copyright (c) 2026 CoworkingView
#
# All modifications and additions to the file contributed by third parties
# remain the property of their copyright owners, unless otherwise agreed
# upon. The license for this file, and modifications and additions to the
# file, is the same license as for the pristine package itself (unless the
# license for the pristine package is not an Open Source License, in which
# case the license is the MIT License). An "Open Source License" is a
# license that conforms to the Open Source Definition (Version 1.9)
# published by the Open Source Initiative.
#
# Please submit bugfixes or comments via
# https://github.com/coworkingview/flex-office-data/issues
#


%global crate coworkingview
# cargo-packaging defines this once it is installed. Keep a fallback so the
# spec still parses while BuildRequires are being collected.
%{!?rust_tier1_arches:%global rust_tier1_arches x86_64 aarch64}

Name:           cwv
Version:        0.1.0
Release:        0
Summary:        Command-line client for the CoworkingView Price Index
License:        MIT
URL:            https://coworkingview.com/en/tools/price-index
# crates.io .crate (gzip tarball). rpm unpacks it by content, not by suffix.
Source0:        https://static.crates.io/crates/%{crate}/%{crate}-%{version}.crate
# Produced by the cargo_vendor source service (or integrations/obs/vendor.sh).
# Layout, as unpacked over the crate: Cargo.lock, .cargo/config.toml, vendor/.
# Not stored in git; committed to the OBS package.
Source1:        vendor.tar.zst
BuildRequires:  cargo-packaging
BuildRequires:  rust >= 1.88
# ring (via rustls) compiles C. Present in the OBS preinstall; required for
# a plain rpmbuild chroot.
BuildRequires:  gcc
BuildRequires:  make
ExclusiveArch:  %{rust_tier1_arches}

%description
cwv is the command-line client for the CoworkingView Price Index:
median, 25th and 75th percentile prices for flexible office space,
city by city, and a search across shared offices, private offices,
meeting rooms, event spaces and virtual offices. It reads a public
API and needs no account.

The program is MIT. The Price Index figures it prints are CC BY 4.0.
Listings of individual spaces belong to their operators.

%prep
%autosetup -n %{crate}-%{version} -p1 -a1

%build
# The crate's release profile strips the binary. Distro builds keep the
# symbols so rpm can split debuginfo. cargo-packaging's rustflags already
# ask for debuginfo=2 and strip=none; the profile would undo that.
export CARGO_PROFILE_RELEASE_STRIP=none
export CARGO_PROFILE_RELEASE_DEBUG=2
%{cargo_build}
mkdir -p completions
%{_builddir}/%{buildsubdir}/target/release/cwv completions bash > completions/cwv
%{_builddir}/%{buildsubdir}/target/release/cwv completions zsh > completions/_cwv
%{_builddir}/%{buildsubdir}/target/release/cwv completions fish > completions/cwv.fish
%{_builddir}/%{buildsubdir}/target/release/cwv man > cwv.1

%install
export CARGO_PROFILE_RELEASE_STRIP=none
export CARGO_PROFILE_RELEASE_DEBUG=2
%{cargo_install}
install -D -m 0644 cwv.1 %{buildroot}%{_mandir}/man1/cwv.1
install -D -m 0644 completions/cwv %{buildroot}%{_datadir}/bash-completion/completions/cwv
install -D -m 0644 completions/_cwv %{buildroot}%{_datadir}/zsh/site-functions/_cwv
install -D -m 0644 completions/cwv.fish %{buildroot}%{_datadir}/fish/vendor_completions.d/cwv.fish

%check
# Offline. The crates.io tarball ships the library and binary unit tests
# and the doctests. The fixture suites under tests/ live only in git.
%{cargo_test}

%files
%license LICENSE
%doc README.md CHANGELOG.md
%{_bindir}/cwv
%{_mandir}/man1/cwv.1*
%{_datadir}/bash-completion/completions/cwv
%{_datadir}/zsh/site-functions/_cwv
%{_datadir}/fish/vendor_completions.d/cwv.fish

# cwv.changes is the Build Service changelog. The same entry is repeated
# here so a plain rpmbuild (the CI container) has one. On OBS the
# .changes file is what gets published.
%changelog
* Wed Nov 04 2026 CoworkingView <info@coworkingview.com> - 0.1.0-0
- Initial package of cwv 0.1.0, the command-line client for the
  CoworkingView Price Index and coworking catalogue search
