# run.ps1 - build (if needed) and launch the anniversary PRG in VICE
# Usage:
#   .\run.ps1                 # build-if-needed + fullscreen (default)
#   .\run.ps1 -Windowed       # force windowed mode
#   .\run.ps1 -SkipBuild      # do not auto-build first

[CmdletBinding()]
param(
    [switch]$Windowed,
    [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"
Push-Location $PSScriptRoot

# Locate VICE (local install via setup-vice.ps1, else PATH).
$localVice = Get-ChildItem -Path (Join-Path $PSScriptRoot "tools\vice") -Recurse -Filter "x64sc.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($localVice) {
    $viceCmd = $localVice.FullName
} else {
    $onPath = Get-Command x64sc -ErrorAction SilentlyContinue
    if ($onPath) { $viceCmd = $onPath.Source }
}

if (-not $viceCmd) {
    Write-Host "VICE (x64sc) not found." -ForegroundColor Red
    Write-Host "Run the setup script first:  .\setup-vice.ps1" -ForegroundColor Yellow
    Pop-Location
    exit 1
}

# Build the .prg if it's missing or older than the source.
$prg = Join-Path $PSScriptRoot "Parallels RAS - Lazy Jones - 20 year edition.prg"
$asm = Join-Path $PSScriptRoot "main.asm"
$needBuild = $false
if (-not $SkipBuild) {
    $needBuild = -not (Test-Path $prg)
    if (-not $needBuild) {
        $needBuild = (Get-Item $asm).LastWriteTime -gt (Get-Item $prg).LastWriteTime
    }
}
if ($needBuild) {
    Write-Host "Building first ..." -ForegroundColor Cyan
    & (Join-Path $PSScriptRoot "build.ps1")
}

if (-not (Test-Path $prg)) {
    Write-Host "Program not found: $prg" -ForegroundColor Red
    Pop-Location
    exit 1
}

if ($Windowed) {
    $viceArgs = @("+fullscreen")
} else {
    $viceArgs = @("-fullscreen")
}

$viceArgs += @("-autostart", $prg)

Write-Host "Launching VICE: $viceCmd $($viceArgs -join ' ')" -ForegroundColor Green
& $viceCmd @viceArgs

Pop-Location
