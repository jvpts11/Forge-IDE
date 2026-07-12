# Build Forge with the LDP3 toolchain and run its headless editor-core self-test.
# Usage:  ./build.ps1
# Requires a built `ldp3` driver (in the LDP3 repo build). `ldp3 build` reads ldp3.toml, compiles every
# .ldp3 under src/ as one program, and links Forge.exe into build-output/.
param(
    [string]$Ldp3 = "C:\Users\jvpts\Documents\GitHub\LDP3\build\bin\Debug\ldp3.exe"
)
$ErrorActionPreference = "Stop"
$here = $PSScriptRoot
Push-Location $here
try {
    Write-Host "== ldp3 build =="
    & $Ldp3 build
    if ($LASTEXITCODE -ne 0) { throw "ldp3 build failed" }

    Write-Host "== self-test =="
    & (Join-Path $here "build-output\Forge.exe")
    if ($LASTEXITCODE -ne 0) { throw "Forge exited $LASTEXITCODE" }
} finally {
    Pop-Location
}
