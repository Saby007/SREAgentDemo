<#
.SYNOPSIS
    Cleans up all Azure resources created for the SRE Agent demo.

.DESCRIPTION
    This script deletes the resource group and all resources within it.

.PARAMETER ResourceGroupName
    Name of the resource group to delete.

.PARAMETER Force
    Skip confirmation prompt.

.EXAMPLE
    .\cleanup.ps1 -ResourceGroupName "rg-sre-demo" -Force
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$ResourceGroupName = "rg-sre-demo",
    
    [Parameter(Mandatory = $false)]
    [switch]$Force
)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "╔═══════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║              Azure SRE Agent Demo - Cleanup                       ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Check if resource group exists
$rgExists = az group exists --name $ResourceGroupName
if ($rgExists -eq "false") {
    Write-Host "   ℹ️  Resource group '$ResourceGroupName' does not exist." -ForegroundColor Yellow
    exit 0
}

# List resources
Write-Host "📋 Resources in '$ResourceGroupName':" -ForegroundColor Yellow
$resources = az resource list --resource-group $ResourceGroupName --output json | ConvertFrom-Json
foreach ($resource in $resources) {
    Write-Host "   - $($resource.name) ($($resource.type))" -ForegroundColor White
}

Write-Host ""

# Confirm deletion
if (-not $Force) {
    Write-Host "⚠️  WARNING: This will delete ALL resources in the resource group!" -ForegroundColor Red
    $confirmation = Read-Host "Type 'yes' to confirm deletion"
    if ($confirmation -ne "yes") {
        Write-Host "   Cleanup cancelled." -ForegroundColor Yellow
        exit 0
    }
}

# Delete resource group
Write-Host ""
Write-Host "🗑️  Deleting resource group '$ResourceGroupName'..." -ForegroundColor Yellow
Write-Host "   This may take several minutes..." -ForegroundColor Yellow

az group delete --name $ResourceGroupName --yes --no-wait

Write-Host ""
Write-Host "✅ Deletion initiated. Resources will be removed in the background." -ForegroundColor Green
Write-Host "   You can check status in Azure Portal or run:" -ForegroundColor White
Write-Host "   az group show --name $ResourceGroupName" -ForegroundColor Yellow
Write-Host ""

# Clean up local files
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$backendEnv = Join-Path $scriptPath "..\backend\.env"
if (Test-Path $backendEnv) {
    Remove-Item $backendEnv -Force
    Write-Host "   🧹 Removed backend/.env file" -ForegroundColor Gray
}

$initSql = Join-Path $scriptPath "init-database.sql"
if (Test-Path $initSql) {
    Remove-Item $initSql -Force
    Write-Host "   🧹 Removed init-database.sql file" -ForegroundColor Gray
}

Write-Host ""
Write-Host "🎉 Cleanup complete!" -ForegroundColor Green
Write-Host ""
