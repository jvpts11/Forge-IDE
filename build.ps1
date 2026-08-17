# Build Forge with the Polaron toolchain and run its headless editor-core self-test.
# Usage:  ./build.ps1
# Requires a built `polaron` driver (in the Polaron repo build). `polaron build` reads polaron.toml,
# compiles every .pol under src/ as one program, and links Forge.exe into build-output/.
param(
    # The Polaron driver. Default: the sibling ..\Polaron repo's dev build, else `polaron` on PATH.
    [string]$Polaron,
    # The Polaron repo root (to bundle the standard library + the language reference next to the exe).
    # Default: $env:POLARON_HOME, else the sibling ..\Polaron, else inferred from the driver's location.
    [string]$PolaronHome
)
$ErrorActionPreference = "Stop"
$here = $PSScriptRoot

# Locate the Polaron toolchain + repo without hard-coding any machine-specific path, so this builds on
# any checkout: prefer the sibling repo's build / what's on PATH / an env override before failing.
if (-not $Polaron) {
    foreach ($cfg in @("build2\bin\Release", "build\bin\Release", "build\bin\Debug")) {
        $sib = Join-Path $here "..\Polaron\$cfg\polaron.exe"
        if (Test-Path $sib) { $Polaron = (Resolve-Path $sib).Path; break }
    }
    if (-not $Polaron) { $Polaron = (Get-Command polaron -ErrorAction SilentlyContinue).Source }
}
if (-not $Polaron -or -not (Test-Path $Polaron)) {
    throw "could not find the polaron driver -- put polaron on PATH, pass -Polaron <path>, or build the sibling Polaron repo."
}
if (-not $PolaronHome) {
    if ($env:POLARON_HOME -and (Test-Path $env:POLARON_HOME)) {
        $PolaronHome = (Resolve-Path $env:POLARON_HOME).Path
    } elseif (Test-Path (Join-Path $here "..\Polaron")) {
        $PolaronHome = (Resolve-Path (Join-Path $here "..\Polaron")).Path
    } else {
        # Infer from the driver layout: <root>\build*\bin\<cfg>\polaron.exe -> <root>
        $cand = Resolve-Path (Join-Path (Split-Path $Polaron -Parent) "..\..\..") -ErrorAction SilentlyContinue
        if ($cand) { $PolaronHome = $cand.Path }
    }
}
Push-Location $here
try {
    Write-Host "== polaron build =="
    & $Polaron build
    if ($LASTEXITCODE -ne 0) { throw "polaron build failed" }

    # The app icon next to the exe, so the running window/taskbar shows it (Win32 WM_SETICON at startup).
    $ico = Join-Path $here "branding\forge.ico"
    if (Test-Path $ico) { Copy-Item $ico (Join-Path $here "build-output\forge.ico") -Force }

    Write-Host "== reference docs =="
    # Bundle the real, complete standard library and the language reference next to the exe, so
    # Help > Standard Library / Language Reference open the true thing rather than a copy of it.
    #
    # THE STANDARD LIBRARY IS A DIRECTORY NOW. It used to be one chunked raw-string literal inside the
    # compiler's main.cpp, and this script reassembled it by hunting for R"..."-delimited segments. It
    # lives in src/prelude/lib/*.pol and is embedded at build time, so the bundle is a copy of those
    # files -- which is also what makes each one openable under its own name.
    $refDir = Join-Path $here "build-output\reference"
    New-Item -ItemType Directory -Force $refDir | Out-Null
    if ($PolaronHome) {
        $preludeDir = Join-Path $PolaronHome "src\prelude\lib"
        if (Test-Path $preludeDir) {
            $parts = Get-ChildItem (Join-Path $preludeDir "*.pol") | Sort-Object Name
            $sb = New-Object System.Text.StringBuilder
            [void]$sb.Append("// Polaron standard library -- the compiler's embedded prelude, bundled for reference.`n")
            [void]$sb.Append("// Read-only: this is the real source every Polaron program is compiled against.`n`n")
            foreach ($p in $parts) {
                [void]$sb.Append("// ---- " + $p.Name + " ----`n")
                [void]$sb.Append([System.IO.File]::ReadAllText($p.FullName))
                [void]$sb.Append("`n")
            }
            [System.IO.File]::WriteAllText((Join-Path $refDir "stdlib.pol"), $sb.ToString())
            Write-Host ("wrote reference/stdlib.pol ({0} chars from {1} files)" -f $sb.Length, $parts.Count)
            # Importable qualified names, for `import` autocomplete: each public type as <namespace>.<Type>.
            $ns = ""
            $imports = New-Object System.Collections.Generic.List[string]
            foreach ($ln in ($sb.ToString() -split "`n")) {
                $t = $ln.Trim()
                if ($t -match '^(public\s+)?namespace\s+([A-Za-z0-9_.]+)') { $ns = $Matches[2] }
                elseif ($t -match '^public\s+(class|interface|enum|struct|record)\s+([A-Za-z_][A-Za-z0-9_]*)') {
                    $nm = $Matches[2]
                    if ($ns -ne "" -and -not $nm.StartsWith("_")) { $imports.Add("$ns.$nm") }
                }
            }
            $uniq = $imports | Sort-Object -Unique
            [System.IO.File]::WriteAllText((Join-Path $refDir "imports.txt"), ($uniq -join "`n"))
            Write-Host ("wrote reference/imports.txt ({0} names)" -f $uniq.Count)
        }
        # The canonical English language reference (docs/reference/), for Help > Language Reference /
        # Keyword Reference. The whole tree is copied so chapter links resolve; the index and the
        # keyword chapter are also surfaced under the names Help opens directly.
        $refSrc = Join-Path $PolaronHome "docs\reference"
        if (Test-Path $refSrc) {
            Copy-Item $refSrc (Join-Path $refDir "language-reference") -Recurse -Force
            Copy-Item (Join-Path $refSrc "README.md") (Join-Path $refDir "language-reference.md") -Force
            $kw = Join-Path $refSrc "guide\12-keyword-reference.md"
            if (Test-Path $kw) { Copy-Item $kw (Join-Path $refDir "keywords.md") -Force }
        }
    }

    Write-Host "== self-test =="
    # Point the self-test at the language server that sits next to the driver, so its live LSP
    # round-trip actually runs (it skips when this is unset). polaron-lsp.exe is built beside polaron.exe.
    $lspExe = Join-Path (Split-Path $Polaron -Parent) "polaron-lsp.exe"
    if (Test-Path $lspExe) { $env:FORGE_LSP = (Resolve-Path $lspExe).Path }
    & (Join-Path $here "build-output\Forge.exe") test
    if ($LASTEXITCODE -ne 0) { throw "Forge exited $LASTEXITCODE" }
} finally {
    Pop-Location
}
