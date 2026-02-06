<#
.SYNOPSIS
    Triggers or resolves the demo incident by toggling Azure SQL public network access.

.DESCRIPTION
    This script simulates an incident by disabling public network access on the SQL Server,
    which prevents all connections including the Web App. The Azure SRE Agent should
    detect this connectivity issue and suggest remediation.

.PARAMETER Action
    The action to perform: 'block' to trigger incident, 'unblock' to manually fix, 'status' to check.

.PARAMETER ResourceGroupName
    Name of the resource group containing the database.

.EXAMPLE
    # Trigger the incident (disable public network access)
    .\trigger-incident.ps1 -Action block

    # Manually fix (enable public network access) - normally SRE Agent does this
    .\trigger-incident.ps1 -Action unblock

    # Check current status
    .\trigger-incident.ps1 -Action status
#>

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("block", "unblock", "status")]
    [string]$Action,
    
    [Parameter(Mandatory = $false)]
    [string]$ResourceGroupName = "rg-sre-demo-india"
)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "╔═══════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║             Azure SRE Agent Demo - Incident Trigger               ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Get SQL Server name
Write-Host "🔍 Finding Azure SQL resources..." -ForegroundColor Yellow

$sqlServers = az sql server list --resource-group $ResourceGroupName --output json 2>$null | ConvertFrom-Json
if ($sqlServers.Count -eq 0) {
    Write-Host "   ❌ No SQL Server found in resource group '$ResourceGroupName'" -ForegroundColor Red
    exit 1
}

$sqlServer = $sqlServers[0]
$sqlServerName = $sqlServer.name
$publicNetworkAccess = $sqlServer.publicNetworkAccess
Write-Host "   ✅ Found SQL Server: $sqlServerName" -ForegroundColor Green

$isBlocked = $publicNetworkAccess -eq "Disabled"
Write-Host "   🌐 Public Network Access: $(if ($isBlocked) { 'DISABLED (blocked)' } else { 'ENABLED (allowed)' })" -ForegroundColor $(if ($isBlocked) { "Red" } else { "Green" })

# Get Web App info
$webApps = az webapp list --resource-group $ResourceGroupName --output json 2>$null | ConvertFrom-Json
$webAppUrl = if ($webApps.Count -gt 0) { "https://$($webApps[0].defaultHostName)" } else { $null }
$webAppName = if ($webApps.Count -gt 0) { $webApps[0].name } else { $null }

switch ($Action) {
    "status" {
        Write-Host ""
        Write-Host "📋 Current Status:" -ForegroundColor Cyan
        Write-Host "   SQL Server:            $sqlServerName" -ForegroundColor White
        Write-Host "   Public Network Access: $(if ($isBlocked) { '❌ DISABLED' } else { '✅ ENABLED' })" -ForegroundColor $(if ($isBlocked) { "Red" } else { "Green" })
        
        if ($webAppUrl) {
            Write-Host ""
            Write-Host "🌐 Testing Web App connectivity..." -ForegroundColor Yellow
            try {
                $response = Invoke-RestMethod -Uri "$webAppUrl/api/health" -TimeoutSec 30 -ErrorAction Stop
                Write-Host "   ✅ Web App Status: $($response.status)" -ForegroundColor Green
                Write-Host "   ✅ Database: $($response.database)" -ForegroundColor Green
            } catch {
                $errorBody = $_.ErrorDetails.Message | ConvertFrom-Json -ErrorAction SilentlyContinue
                if ($errorBody) {
                    Write-Host "   ❌ Web App Status: $($errorBody.status)" -ForegroundColor Red
                    Write-Host "   ❌ Database: $($errorBody.database)" -ForegroundColor Red
                    Write-Host "   ❌ Error: $($errorBody.error)" -ForegroundColor Red
                } else {
                    Write-Host "   ❌ Web App cannot connect to database!" -ForegroundColor Red
                }
            }
        }
    }
    
    "block" {
        Write-Host ""
        if ($isBlocked) {
            Write-Host "⚠️  Public network access is already DISABLED!" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "🌐 Testing Web App to confirm incident is active..." -ForegroundColor Yellow
            if ($webAppUrl) {
                try {
                    $response = Invoke-RestMethod -Uri "$webAppUrl/api/health" -TimeoutSec 30 -ErrorAction Stop
                    Write-Host "   ⚠️  Web App still connected (cached connection)" -ForegroundColor Yellow
                    Write-Host "   Restarting Web App to break connection pool..." -ForegroundColor Yellow
                    az webapp restart --name $webAppName --resource-group $ResourceGroupName --output none 2>$null
                    Start-Sleep -Seconds 10
                } catch {
                    Write-Host "   ✅ Incident is active - Web App is disconnected!" -ForegroundColor Green
                }
            }
            exit 0
        }
        
        Write-Host "🔴 TRIGGERING INCIDENT: Disabling SQL Server public network access..." -ForegroundColor Red
        Write-Host "   This will prevent ALL connections to the database." -ForegroundColor Yellow
        Write-Host ""
        
        # Disable public network access using REST API (az cli has a bug with RetentionDays)
        $subscriptionId = (az account show --query id -o tsv)
        $token = (az account get-access-token --query accessToken -o tsv)
        $uri = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Sql/servers/$sqlServerName`?api-version=2023-08-01"
        $body = @{ properties = @{ publicNetworkAccess = "Disabled" } } | ConvertTo-Json
        Invoke-RestMethod -Uri $uri -Method Patch -Headers @{ Authorization = "Bearer $token"; "Content-Type" = "application/json" } -Body $body | Out-Null
        
        Write-Host "   ✅ Public network access DISABLED!" -ForegroundColor Green
        
        # Restart Web App to break existing connection pool
        if ($webAppName) {
            Write-Host "   🔄 Restarting Web App to break connection pool..." -ForegroundColor Yellow
            az webapp restart --name $webAppName --resource-group $ResourceGroupName --output none 2>$null
            Start-Sleep -Seconds 15
        }
        
        Write-Host ""
        Write-Host "╔═══════════════════════════════════════════════════════════════════╗" -ForegroundColor Red
        Write-Host "║                    🚨 INCIDENT TRIGGERED! 🚨                      ║" -ForegroundColor Red
        Write-Host "╚═══════════════════════════════════════════════════════════════════╝" -ForegroundColor Red
        Write-Host ""
        Write-Host "📋 What's happening:" -ForegroundColor Cyan
        Write-Host "   1. SQL Server public network access is DISABLED" -ForegroundColor White
        Write-Host "   2. Web App cannot connect to database" -ForegroundColor White
        Write-Host "   3. Health check fails → Azure Monitor alert fires" -ForegroundColor White
        Write-Host "   4. Azure SRE Agent receives the alert" -ForegroundColor White
        Write-Host ""
        Write-Host "👀 Watch the Azure SRE Agent:" -ForegroundColor Cyan
        Write-Host "   - Detects health check failure" -ForegroundColor White
        Write-Host "   - Investigates SQL Server configuration" -ForegroundColor White
        Write-Host "   - RCA: 'Public Network Access is Disabled'" -ForegroundColor White
        Write-Host "   - Fix: 'Enable Public Network Access'" -ForegroundColor White
        Write-Host ""
        Write-Host "🔗 SRE Agent Portal: https://aka.ms/sreagent/portal" -ForegroundColor Yellow
        if ($webAppUrl) {
            Write-Host "🌐 Web App (broken): $webAppUrl" -ForegroundColor Yellow
        }
        
        # Verify incident is active
        Write-Host ""
        Write-Host "🔍 Verifying incident is active..." -ForegroundColor Yellow
        if ($webAppUrl) {
            try {
                $response = Invoke-RestMethod -Uri "$webAppUrl/api/health" -TimeoutSec 30 -ErrorAction Stop
                Write-Host "   ⚠️  Web App still responding (may need more time)" -ForegroundColor Yellow
            } catch {
                Write-Host "   ✅ Confirmed: Web App is DISCONNECTED from database!" -ForegroundColor Green
            }
        }
    }
    
    "unblock" {
        Write-Host ""
        if (-not $isBlocked) {
            Write-Host "✅ Public network access is already ENABLED!" -ForegroundColor Green
            exit 0
        }
        
        Write-Host "🟢 RESOLVING INCIDENT: Enabling SQL Server public network access..." -ForegroundColor Green
        Write-Host "   Note: Azure SRE Agent would normally suggest this fix." -ForegroundColor Yellow
        Write-Host ""
        
        # Enable public network access using REST API (az cli has a bug with RetentionDays)
        $subscriptionId = (az account show --query id -o tsv)
        $token = (az account get-access-token --query accessToken -o tsv)
        $uri = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Sql/servers/$sqlServerName`?api-version=2023-08-01"
        $body = @{ properties = @{ publicNetworkAccess = "Enabled" } } | ConvertTo-Json
        Invoke-RestMethod -Uri $uri -Method Patch -Headers @{ Authorization = "Bearer $token"; "Content-Type" = "application/json" } -Body $body | Out-Null
        
        Write-Host "   ✅ Public network access ENABLED!" -ForegroundColor Green
        
        # Also ensure the Azure services firewall rule exists
        Write-Host "   🔥 Ensuring Azure services firewall rule exists..." -ForegroundColor Yellow
        az sql server firewall-rule create `
            --resource-group $ResourceGroupName `
            --server $sqlServerName `
            --name "AllowAllWindowsAzureIps" `
            --start-ip-address "0.0.0.0" `
            --end-ip-address "0.0.0.0" `
            --output none 2>$null
        
        Write-Host "   ✅ Firewall rule restored!" -ForegroundColor Green
        
        # Verify connectivity
        Write-Host ""
        Write-Host "🔍 Verifying connectivity restored..." -ForegroundColor Yellow
        Start-Sleep -Seconds 5
        
        if ($webAppUrl) {
            $retries = 3
            $connected = $false
            for ($i = 1; $i -le $retries; $i++) {
                try {
                    $response = Invoke-RestMethod -Uri "$webAppUrl/api/health" -TimeoutSec 30 -ErrorAction Stop
                    Write-Host "   ✅ Web App Status: $($response.status)" -ForegroundColor Green
                    Write-Host "   ✅ Database: $($response.database)" -ForegroundColor Green
                    $connected = $true
                    break
                } catch {
                    if ($i -lt $retries) {
                        Write-Host "   ⏳ Waiting for connection to restore (attempt $i/$retries)..." -ForegroundColor Yellow
                        Start-Sleep -Seconds 5
                    }
                }
            }
            if (-not $connected) {
                Write-Host "   ⏳ Connection may take a moment to restore. Refresh the Web App." -ForegroundColor Yellow
            }
        }
        
        Write-Host ""
        Write-Host "╔═══════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
        Write-Host "║                    ✅ INCIDENT RESOLVED! ✅                       ║" -ForegroundColor Green
        Write-Host "╚═══════════════════════════════════════════════════════════════════╝" -ForegroundColor Green
        Write-Host ""
        Write-Host "   SQL Server is now accessible. Web App should recover." -ForegroundColor White
        if ($webAppUrl) {
            Write-Host "   🌐 Web App: $webAppUrl" -ForegroundColor Yellow
        }
    }
}

Write-Host ""
