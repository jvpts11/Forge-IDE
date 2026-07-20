# Build Forge with the LDP3 toolchain and run its headless editor-core self-test.
# Usage:  ./build.ps1
# Requires a built `ldp3` driver (in the LDP3 repo build). `ldp3 build` reads ldp3.toml, compiles every
# .ldp3 under src/ as one program, and links Forge.exe into build-output/.
param(
    # The LDP3 driver. Default: the sibling ..\LDP3 repo's dev build, else `ldp3` on PATH.
    [string]$Ldp3,
    # The LDP3 repo root (to bundle the stdlib prelude + spec next to the exe). Default:
    # $env:LDP3_HOME, else the sibling ..\LDP3, else inferred from the driver's location.
    [string]$Ldp3Home
)
$ErrorActionPreference = "Stop"
$here = $PSScriptRoot

# Locate the LDP3 toolchain + repo without hard-coding any machine-specific path, so this builds on any
# checkout: prefer what's on PATH / the sibling repo / an env override before failing with guidance.
if (-not $Ldp3) {
    # Prefer the sibling repo's dev build (what you get when hacking on both), then whatever is on PATH
    # (an installed toolchain, for anyone building Forge without the LDP3 source checked out).
    $sib = Join-Path $here "..\LDP3\build\bin\Debug\ldp3.exe"
    if (Test-Path $sib) {
        $Ldp3 = (Resolve-Path $sib).Path
    } else {
        $Ldp3 = (Get-Command ldp3 -ErrorAction SilentlyContinue).Source
    }
}
if (-not $Ldp3 -or -not (Test-Path $Ldp3)) {
    throw "could not find the ldp3 driver -- put ldp3 on PATH, pass -Ldp3 <path>, or build the sibling LDP3 repo."
}
if (-not $Ldp3Home) {
    if ($env:LDP3_HOME -and (Test-Path $env:LDP3_HOME)) {
        $Ldp3Home = (Resolve-Path $env:LDP3_HOME).Path
    } elseif (Test-Path (Join-Path $here "..\LDP3")) {
        $Ldp3Home = (Resolve-Path (Join-Path $here "..\LDP3")).Path
    } else {
        # Infer from the driver layout: <root>\build\bin\<cfg>\ldp3.exe -> <root>
        $cand = Resolve-Path (Join-Path (Split-Path $Ldp3 -Parent) "..\..\..") -ErrorAction SilentlyContinue
        if ($cand) { $Ldp3Home = $cand.Path }
    }
}
Push-Location $here
try {
    Write-Host "== ldp3 build =="
    & $Ldp3 build
    if ($LASTEXITCODE -ne 0) { throw "ldp3 build failed" }

    # The app icon next to the exe, so the running window/taskbar shows it (Win32 WM_SETICON at startup).
    $ico = Join-Path $here "branding\forge.ico"
    if (Test-Path $ico) { Copy-Item $ico (Join-Path $here "build-output\forge.ico") -Force }

    Write-Host "== reference docs =="
    # Bundle the real, complete standard library (the compiler's embedded prelude) and the language
    # specification next to the exe, so Help > Standard Library / Language Reference can open them in a
    # browsable tab. The prelude lives as one chunked raw-string literal (kPreludeSource) in the LDP3
    # compiler; concatenate every R"LDP3( ... )LDP3" segment back into a single .ldp3 file.
    $refDir = Join-Path $here "build-output\reference"
    New-Item -ItemType Directory -Force $refDir | Out-Null
    $mainCpp = Join-Path (Split-Path $Ldp3 -Parent) "..\..\..\src\cli\main.cpp"
    if (-not (Test-Path $mainCpp) -and $Ldp3Home) { $mainCpp = Join-Path $Ldp3Home "src\cli\main.cpp" }
    if (Test-Path $mainCpp) {
        $src = [System.IO.File]::ReadAllText($mainCpp)
        $start = $src.IndexOf("kPreludeSource")
        if ($start -ge 0) {
            $sb = New-Object System.Text.StringBuilder
            [void]$sb.Append("// LDP3 standard library -- the compiler's embedded prelude, bundled for reference.`n")
            [void]$sb.Append("// Read-only: this is the real source every LDP3 program is compiled against.`n`n")
            $i = $start
            while ($true) {
                $a = $src.IndexOf('R"LDP3(', $i)
                if ($a -lt 0) { break }
                $b = $src.IndexOf(')LDP3"', $a)
                if ($b -lt 0) { break }
                $cs = $a + 7
                [void]$sb.Append($src.Substring($cs, $b - $cs))
                $i = $b + 6
                $j = $i
                while ($j -lt $src.Length -and " `t`r`n".IndexOf($src[$j]) -ge 0) { $j++ }
                if ($j -lt $src.Length -and $src[$j] -eq ';') { break }
            }
            [System.IO.File]::WriteAllText((Join-Path $refDir "stdlib.ldp3"), $sb.ToString())
            Write-Host ("wrote reference/stdlib.ldp3 ({0} chars)" -f $sb.Length)
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
    }
    if ($Ldp3Home) {
        # Bundle the canonical English language reference (docs/reference/) for Help > Language
        # Reference / Keyword Reference. The whole tree is copied so chapter links resolve; the
        # index and the keyword chapter are also surfaced under the names Help opens directly.
        $refSrc = Join-Path $Ldp3Home "docs\reference"
        if (Test-Path $refSrc) {
            Copy-Item $refSrc (Join-Path $refDir "language-reference") -Recurse -Force
            Copy-Item (Join-Path $refSrc "README.md") (Join-Path $refDir "language-reference.md") -Force
            Copy-Item (Join-Path $refSrc "guide\11-keyword-reference.md") (Join-Path $refDir "keywords.md") -Force
        }
    }

    Write-Host "== self-test =="
    # Point the self-test at the language server that sits next to the driver, so its live LSP
    # round-trip actually runs (it skips when this is unset). ldp3-lsp.exe is built beside ldp3.exe.
    $lspExe = Join-Path (Split-Path $Ldp3 -Parent) "ldp3-lsp.exe"
    if (Test-Path $lspExe) { $env:FORGE_LSP = (Resolve-Path $lspExe).Path }
    & (Join-Path $here "build-output\Forge.exe") test
    if ($LASTEXITCODE -ne 0) { throw "Forge exited $LASTEXITCODE" }
} finally {
    Pop-Location
}
