<#
.SYNOPSIS
    Builds the C64 custom Bicep extension and deploys the desired state
    to the physical C64 Ultimate.

.NOTES
    Requirements:
      - .NET 8 SDK (dotnet)
      - Bicep CLI v0.37+ (bicep) with localDeploy support
      - C64 Ultimate with "Web Remote Control Service" enabled

    Usage:
      ./deploy.ps1            # build + publish extension + local-deploy
      ./deploy.ps1 -SkipBuild # redeploy only (extension already published)
#>
param(
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

# Resolve the Bicep CLI: prefer PATH, fall back to the Azure CLI-managed copy.
$bicep = Get-Command bicep -ErrorAction SilentlyContinue
$bicep = if ($bicep) { $bicep.Source } else { "$env:USERPROFILE\.azure\bin\bicep.exe" }
if (-not (Test-Path $bicep)) { throw 'Bicep CLI not found. Install it via "az bicep install" or winget.' }

if (-not $SkipBuild) {
    Write-Host '==> Publishing extension binaries (win-x64 + win-arm64)...' -ForegroundColor Cyan
    # Publish outside the project folder to avoid recursive publish output.
    foreach ($rid in 'win-x64', 'win-arm64') {
        dotnet publish "$root\extension" -r $rid -c Release -o "$root\artifacts\$rid"
        if ($LASTEXITCODE -ne 0) { throw "dotnet publish ($rid) failed" }
    }

    Write-Host '==> Publishing Bicep extension package...' -ForegroundColor Cyan
    & $bicep publish-extension `
        --bin-win-x64 "$root\artifacts\win-x64\c64extension.exe" `
        --bin-win-arm64 "$root\artifacts\win-arm64\c64extension.exe" `
        --target "$root\bin\c64extension" `
        --force
    if ($LASTEXITCODE -ne 0) { throw 'bicep publish-extension failed' }
}

Write-Host '==> Deploying desired state to the C64...' -ForegroundColor Cyan
& $bicep local-deploy "$root\main.bicepparam"
if ($LASTEXITCODE -ne 0) { throw 'bicep local-deploy failed' }

Write-Host '==> Done! Check your C64 screen.' -ForegroundColor Green
