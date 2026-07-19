# Build the Forge .msi end to end: stage the self-contained bundle (Forge + the LDP3 toolchain), then
# compile the WiX package. Prereqs: a Release build of the LDP3 binaries in the sibling LDP3 repo
# (cmake --build build --config Release there), LLVM on PATH or in C:\Program Files\LLVM, and the WiX tool
# (dotnet tool install --global wix).
#
#   ./build-msi.ps1                       # -> installer/dist/Forge-0.2.0.msi
param(
    [string]$Config = "Release",
    [string]$Version = "0.2.0"
)
$ErrorActionPreference = "Stop"
$here = $PSScriptRoot
# WiX resolves the .wxs's relative paths (../branding/forge.ico, dist\stage\...) against the CWD, not the
# .wxs location -- so run from installer/, regardless of the caller's CWD.
Set-Location $here

Write-Host "== staging Forge bundle =="
& "$here\pack-forge.ps1" -Config $Config

$wix = (Get-Command wix -ErrorAction SilentlyContinue).Source
if (-not $wix) { $wix = Join-Path $env:USERPROFILE ".dotnet\tools\wix.exe" }
if (-not (Test-Path $wix)) { throw "wix not found; run: dotnet tool install --global wix" }

$out = Join-Path $here "dist\Forge-$Version.msi"
Write-Host "== building $out =="
& $wix build "$here\forge.wxs" -arch x64 -o $out
if ($LASTEXITCODE -ne 0) { throw "wix build failed" }
Write-Host "OK -> $out"
