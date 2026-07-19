# Stage a self-contained Forge bundle for the .msi. The goal: installing Forge gives a user the IDE AND
# everything it drives -- edit, build, run, and debug LDP3 -- on a bare Windows 10/11 x64 machine with
# nothing else installed. We reuse the LDP3 toolchain's own pack-bundle.ps1 to stage the compiler/driver/
# clang/lld/CRT + lldb-dap + python311, then drop Forge.exe, its reference docs, and its icon in beside
# them so Forge finds ldp3, clang, and lldb-dap as siblings on PATH.
#
#   ./pack-forge.ps1                      # stages installer/dist/stage/app from Release builds
#
# Layout produced (a single install folder; everything is a sibling of Forge.exe):
#   dist/stage/app/   Forge.exe forge.ico reference\**  +  ldp3.exe ldp3c.exe clang.exe lld-link.exe
#                     lldb-dap.exe liblldb.dll python311.* ldp3_rt.lib *.dll  + lib\*.lib
param(
    [string]$Config = "Release",
    [string]$RepoRoot = (Resolve-Path "$PSScriptRoot\.."),
    [string]$Ldp3Repo = "",
    [string]$LlvmBin  = "",
    [string]$PythonEmbed = ""
)
$ErrorActionPreference = "Stop"
$here = $PSScriptRoot

# The LDP3 toolchain repo (sibling by default) -- its pack-bundle.ps1 stages the core toolchain we bundle.
if (-not $Ldp3Repo) { $Ldp3Repo = (Resolve-Path "$RepoRoot\..\LDP3").Path }
$ldp3Pack = Join-Path $Ldp3Repo "installer\pack-bundle.ps1"
if (-not (Test-Path $ldp3Pack)) { throw "LDP3 installer not found at $ldp3Pack; pass -Ldp3Repo <path>" }

# 1) Build Forge (produces build-output\Forge.exe + reference\ + forge.ico).
Write-Host "== building Forge =="
& (Join-Path $RepoRoot "build.ps1")
if ($LASTEXITCODE -ne 0) { throw "Forge build failed" }

# 2) Stage the LDP3 core toolchain with its own packer (a Release build of LDP3 must exist).
Write-Host "== staging the LDP3 toolchain =="
$packArgs = @{ Config = $Config }
if ($LlvmBin)     { $packArgs.LlvmBin = $LlvmBin }
if ($PythonEmbed) { $packArgs.PythonEmbed = $PythonEmbed }
& $ldp3Pack @packArgs
$ldp3Core = Join-Path $Ldp3Repo "installer\dist\stage\core"
if (-not (Test-Path (Join-Path $ldp3Core "ldp3.exe"))) { throw "LDP3 core staging failed (no ldp3.exe in $ldp3Core)" }

# 3) Assemble Forge's stage: the toolchain, then Forge and its runtime files, all as siblings.
$stage = Join-Path $here "dist\stage"
$app = Join-Path $stage "app"     # the toolchain + reference docs + icon (harvested wholesale)
$main = Join-Path $stage "main"   # Forge.exe alone, so the .wxs can give it a stable File Id
Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $app | Out-Null
New-Item -ItemType Directory -Force -Path $main | Out-Null
Copy-Item (Join-Path $ldp3Core "*") $app -Recurse -Force
$bo = Join-Path $RepoRoot "build-output"
Copy-Item (Join-Path $bo "Forge.exe") $main
Copy-Item (Join-Path $bo "forge.ico") $app
Copy-Item (Join-Path $bo "reference") $app -Recurse -Force

Write-Host ("staged Forge bundle: app={0:N0} MB" -f ((Get-ChildItem $app -Recurse | Measure-Object Length -Sum).Sum / 1MB))
Write-Host "-> $stage"
