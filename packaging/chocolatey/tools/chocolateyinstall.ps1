$ErrorActionPreference = 'Stop'

$toolsDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$version  = '0.1.0'

$packageArgs = @{
  packageName    = $env:ChocolateyPackageName
  unzipLocation  = $toolsDir
  # Static x86_64 Windows build attached to the GitHub release.
  url64bit       = "https://github.com/coworkingview/flex-office-data/releases/download/rust-v$version/cwv-$version-x86_64-pc-windows-msvc.zip"
  checksum64     = '616bc646fb81acc49bf600caa6df8340f37a1f446d8e8a3aec428631a3f9076b'
  checksumType64 = 'sha256'
}

# Unzips cwv.exe into the package's tools folder; Chocolatey creates the
# `cwv` shim on PATH automatically and removes it on uninstall.
Install-ChocolateyZipPackage @packageArgs
