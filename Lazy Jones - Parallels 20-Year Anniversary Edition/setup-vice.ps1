# setup-vice.ps1
# Downloads the VICE Commodore 64 emulator (Windows build) into
# c64\tools\vice so you can test the anniversary PRG without a system install.
#
# VICE is hosted on GitHub releases (reachable here), so this should
# download automatically.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File .\c64\setup-vice.ps1
#
# After it finishes, run:  .\c64\run.ps1

$ErrorActionPreference = "Stop"
$root     = $PSScriptRoot
$toolsDir = Join-Path $root "tools"
$viceDir  = Join-Path $toolsDir "vice"
$zipPath  = Join-Path $toolsDir "vice-win.zip"

New-Item -ItemType Directory -Force -Path $toolsDir | Out-Null

# If x64sc.exe already exists, we're done.
$existing = Get-ChildItem -Path $viceDir -Recurse -Filter "x64sc.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($existing) {
    Write-Host "VICE already present: $($existing.FullName)" -ForegroundColor Green
    exit 0
}

# Query the GitHub API for the latest VICE Windows (GTK3, x64) release asset.
Write-Host "Looking up the latest VICE release on GitHub ..." -ForegroundColor Cyan
$apiUrl = "https://api.github.com/repos/VICE-Team/svn-mirror/releases/latest"
$asset  = $null
try {
    $headers = @{ "User-Agent" = "lazyjones-setup"; "Accept" = "application/vnd.github+json" }
    $rel = Invoke-RestMethod -Uri $apiUrl -Headers $headers -TimeoutSec 30
    # Prefer a 64-bit GTK3 Windows zip.
    $asset = $rel.assets |
        Where-Object { $_.name -match 'win64' -and $_.name -match '\.zip$' } |
        Select-Object -First 1
    if (-not $asset) {
        $asset = $rel.assets |
            Where-Object { $_.name -match 'win' -and $_.name -match '\.zip$' } |
            Select-Object -First 1
    }
} catch {
    Write-Host "GitHub API lookup failed: $($_.Exception.Message)" -ForegroundColor DarkYellow
}

$downloaded = $false
if ($asset) {
    Write-Host "Downloading $($asset.name) ..." -ForegroundColor Cyan
    try {
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zipPath -UserAgent "Mozilla/5.0" -MaximumRedirection 10
        if ((Test-Path $zipPath) -and ((Get-Item $zipPath).Length -gt 1mb)) { $downloaded = $true }
    } catch {
        Write-Host "  download failed: $($_.Exception.Message)" -ForegroundColor DarkYellow
    }
}

if (-not $downloaded) {
    Write-Host ""
    Write-Host "Automatic download failed." -ForegroundColor Red
    Write-Host "Manual steps:" -ForegroundColor Yellow
    Write-Host "  1. Open https://vice-emu.sourceforge.io/index.html#download"
    Write-Host "     (or https://github.com/VICE-Team/svn-mirror/releases )"
    Write-Host "  2. Download the Windows (win64, GTK3) zip."
    Write-Host "  3. Save it as: $zipPath"
    Write-Host "  4. Re-run this script (it will just unzip an already-downloaded file)."
    if (-not (Test-Path $zipPath)) { exit 1 }
    Write-Host "Found an existing $zipPath - continuing to unzip it." -ForegroundColor Green
}

Write-Host "Extracting to $viceDir ..." -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path $viceDir | Out-Null
Expand-Archive -Path $zipPath -DestinationPath $viceDir -Force

$exe = Get-ChildItem -Path $viceDir -Recurse -Filter "x64sc.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($exe) {
    Write-Host "VICE ready: $($exe.FullName)" -ForegroundColor Green
    Write-Host "Now run:  .\c64\run.ps1" -ForegroundColor Green
} else {
    Write-Host "Unzipped, but x64sc.exe not found. Check the contents of $viceDir." -ForegroundColor Red
    exit 1
}
