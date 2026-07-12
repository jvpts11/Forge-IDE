# Build and run Forge's headless editor-core self-test.
# Usage:  ./build.ps1            # compile src/forge.ldp3 -> forge.exe and run it
# Requires a built ldp3c (in the LDP3 repo) and clang (C:\Program Files\LLVM).
param(
    [string]$Ldp3c = "C:\Users\jvpts\Documents\GitHub\LDP3\build\bin\Debug\ldp3c.exe",
    [string]$Clang = "C:\Program Files\LLVM\bin\clang.exe",
    [string]$Runtime = "C:\Users\jvpts\Documents\GitHub\LDP3\build\bin\Debug\ldp3_rt.lib"
)
$ErrorActionPreference = "Stop"
$here = $PSScriptRoot
$src = Join-Path $here "src\forge.ldp3"
$ll  = Join-Path $here "forge.ll"
$exe = Join-Path $here "forge.exe"

Write-Host "== compiling $src =="
& $Ldp3c $src -O2 -o $ll
if ($LASTEXITCODE -ne 0) { throw "ldp3c failed" }

Write-Host "== linking =="
& $Clang -O2 $ll $Runtime -o $exe -llegacy_stdio_definitions
if ($LASTEXITCODE -ne 0) { throw "clang link failed" }

Write-Host "== running self-test =="
& $exe
