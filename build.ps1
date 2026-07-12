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

    Write-Host "== reference docs =="
    # Bundle the real, complete standard library (the compiler's embedded prelude) and the language
    # specification next to the exe, so Help > Standard Library / Language Reference can open them in a
    # browsable tab. The prelude lives as one chunked raw-string literal (kPreludeSource) in the LDP3
    # compiler; concatenate every R"LDP3( ... )LDP3" segment back into a single .ldp3 file.
    $refDir = Join-Path $here "build-output\reference"
    New-Item -ItemType Directory -Force $refDir | Out-Null
    $mainCpp = Join-Path (Split-Path $Ldp3 -Parent) "..\..\..\src\cli\main.cpp"
    if (-not (Test-Path $mainCpp)) { $mainCpp = "C:\Users\jvpts\Documents\GitHub\LDP3\src\cli\main.cpp" }
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
        }
    }
    $spec = "C:\Users\jvpts\Documents\GitHub\LDP3\docs\LDP3_specification.md"
    if (Test-Path $spec) { Copy-Item $spec (Join-Path $refDir "language-reference.md") -Force }
    $kw = "C:\Users\jvpts\Documents\GitHub\LDP3\docs\LDP3_keywords.md"
    if (Test-Path $kw) { Copy-Item $kw (Join-Path $refDir "keywords.md") -Force }

    Write-Host "== self-test =="
    & (Join-Path $here "build-output\Forge.exe") test
    if ($LASTEXITCODE -ne 0) { throw "Forge exited $LASTEXITCODE" }
} finally {
    Pop-Location
}
