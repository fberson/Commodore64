# build.ps1 - build the C64 Lazy Jones (Parallels edition) .prg with ACME
# Usage:  ./build.ps1        (from the c64 folder)
# Requires ACME cross-assembler on PATH (see README.md for install steps).

$ErrorActionPreference = "Stop"
Push-Location $PSScriptRoot

# Prefer a locally-downloaded ACME (via setup-acme.ps1), else fall back to PATH.
$localAcme = Get-ChildItem -Path (Join-Path $PSScriptRoot "tools\acme") -Recurse -Filter "acme.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($localAcme) {
    $acmeCmd = $localAcme.FullName
} else {
    $onPath = Get-Command acme -ErrorAction SilentlyContinue
    if ($onPath) {
        $acmeCmd = $onPath.Source
    }
}

if (-not $acmeCmd) {
    Write-Host "ACME not found." -ForegroundColor Red
    Write-Host "Run the setup script first:  .\setup-acme.ps1" -ForegroundColor Yellow
    Write-Host "(or install ACME and put acme.exe on your PATH)" -ForegroundColor Yellow
    Pop-Location
    exit 1
}

Write-Host "Using ACME: $acmeCmd" -ForegroundColor DarkCyan
$prg = Join-Path $PSScriptRoot "Parallels RAS - Lazy Jones - 20 year edition.prg"
Write-Host "Assembling main.asm -> $prg ..." -ForegroundColor Cyan
& $acmeCmd -f cbm -o $prg main.asm
$assemblerExitCode = $LASTEXITCODE

if ($assemblerExitCode -eq 0 -and (Test-Path -LiteralPath $prg)) {
    Write-Host "Build OK: $prg" -ForegroundColor Green
    Write-Host "Run in VICE:  x64sc `"$prg`"" -ForegroundColor Green
    Write-Host "Or copy the PRG to the Ultimate 64 USB/SD and load it." -ForegroundColor Green
} else {
    Pop-Location
    throw "Build failed (ACME exit code: $assemblerExitCode)."
}

Pop-Location
