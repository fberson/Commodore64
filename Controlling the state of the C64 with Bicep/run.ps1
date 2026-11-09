<#
.SYNOPSIS
    Deploys the desired state in main.bicepparam to the C64 Ultimate.
    Assumes the extension is already built and published (run deploy.ps1 once first).
#>

$ErrorActionPreference = 'Stop'
$root = 'C:\Users\freek\OneDrive\Sessions\C64 Desired State\'

# Resolve the Bicep CLI: prefer PATH, fall back to the Azure CLI-managed copy.
$bicep = Get-Command bicep -ErrorAction SilentlyContinue
$bicep = if ($bicep) { $bicep.Source } else { "$env:USERPROFILE\.azure\bin\bicep.exe" }
if (-not (Test-Path $bicep)) { throw 'Bicep CLI not found. Install it via "az bicep install" or winget.' }

& $bicep local-deploy "$root\main.bicepparam"
