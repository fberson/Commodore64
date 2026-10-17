# setup-acme.ps1
# Downloads the ACME cross-assembler (Windows build) into c64\tools\acme
# so you can build the C64 program without a system-wide install.
#
# Usage (from anywhere):
#   powershell -ExecutionPolicy Bypass -File .\c64\setup-acme.ps1
#
# After it finishes, run:  .\c64\build.ps1

$ErrorActionPreference = "Stop"
$root      = $PSScriptRoot
$toolsDir  = Join-Path $root "tools"
$acmeDir   = Join-Path $toolsDir "acme"
$zipPath   = Join-Path $toolsDir "acme-win.zip"

New-Item -ItemType Directory -Force -Path $toolsDir | Out-Null

# If acme.exe already exists, we're done.
$existing = Get-ChildItem -Path $acmeDir -Recurse -Filter "acme.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($existing) {
    Write-Host "ACME already present: $($existing.FullName)" -ForegroundColor Green
    exit 0
}

# Candidate download URLs (SourceForge Windows builds). We try newest first.
$urls = @(
    "https://sourceforge.net/projects/acme-crossass/files/win32/acme0.97win.zip/download",
    "https://downloads.sourceforge.net/project/acme-crossass/win32/acme0.97win.zip",
    "https://sourceforge.net/projects/acme-crossass/files/win32/Acme%200.96.4/acme0.96.4win.zip/download"
)

$downloaded = $false
foreach ($url in $urls) {
    try {
        Write-Host "Trying: $url" -ForegroundColor Cyan
        # SourceForge needs a normal user agent and follows redirects.
        Invoke-WebRequest -Uri $url -OutFile $zipPath -UserAgent "Mozilla/5.0" -MaximumRedirection 10
        if ((Test-Path $zipPath) -and ((Get-Item $zipPath).Length -gt 10kb)) {
            $downloaded = $true
            break
        }
    } catch {
        Write-Host "  failed: $($_.Exception.Message)" -ForegroundColor DarkYellow
    }
}

if (-not $downloaded) {
    Write-Host ""
    Write-Host "Automatic download failed (SourceForge may be blocking the request)." -ForegroundColor Red
    Write-Host "Manual steps:" -ForegroundColor Yellow
    Write-Host "  1. Open https://sourceforge.net/projects/acme-crossass/files/win32/"
    Write-Host "  2. Download the newest acmeXXXwin.zip"
    Write-Host "  3. Save it as: $zipPath"
    Write-Host "  4. Re-run this script (it will just unzip an already-downloaded file)."
    if (-not (Test-Path $zipPath)) { exit 1 }
    Write-Host "Found an existing $zipPath - continuing to unzip it." -ForegroundColor Green
}

Write-Host "Extracting to $acmeDir ..." -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path $acmeDir | Out-Null
Expand-Archive -Path $zipPath -DestinationPath $acmeDir -Force

$acmeExe = Get-ChildItem -Path $acmeDir -Recurse -Filter "acme.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($acmeExe) {
    Write-Host "ACME ready: $($acmeExe.FullName)" -ForegroundColor Green
    Write-Host "Now run:  .\c64\build.ps1" -ForegroundColor Green
} else {
    Write-Host "Unzipped, but acme.exe not found. Check the contents of $acmeDir." -ForegroundColor Red
    exit 1
}
