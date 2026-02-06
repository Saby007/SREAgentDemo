<#
.SYNOPSIS
    Deploys a Windows VM with monitoring for the CPU spike demo scenario.

.DESCRIPTION
    This script deploys:
    - Windows Server 2022 VM with Azure Monitor Agent
    - CPU High alert (Sev 2)
    - Uses existing Log Analytics workspace from rg-sre-demo-india

.PARAMETER ResourceGroupName
    Name of the resource group (default: rg-sre-demo-india).

.PARAMETER VmName
    Name of the VM (default: sre-demo-vm).

.PARAMETER AdminUsername
    VM admin username (default: sredemoadmin).

.PARAMETER AdminPassword
    VM admin password (will prompt if not provided).

.EXAMPLE
    .\deploy-vm.ps1 -AdminPassword (ConvertTo-SecureString "YourP@ssw0rd123!" -AsPlainText -Force)
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$ResourceGroupName = "rg-sre-demo-india",
    
    [Parameter(Mandatory = $false)]
    [string]$VmName = "sre-demo-vm",
    
    [Parameter(Mandatory = $false)]
    [string]$AdminUsername = "sredemoadmin",
    
    [Parameter(Mandatory = $false)]
    [SecureString]$AdminPassword
)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "╔═══════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║      Azure SRE Agent Demo - VM CPU Spike Scenario Deployment      ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Check if password provided
if (-not $AdminPassword) {
    $AdminPassword = Read-Host -Prompt "Enter VM Admin Password" -AsSecureString
}

$plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($AdminPassword))

# Get existing resources
Write-Host "🔍 Finding existing resources..." -ForegroundColor Yellow
$logAnalytics = az monitor log-analytics workspace list --resource-group $ResourceGroupName --query "[0]" --output json | ConvertFrom-Json
if (-not $logAnalytics) {
    Write-Host "   ❌ No Log Analytics workspace found in $ResourceGroupName" -ForegroundColor Red
    exit 1
}
Write-Host "   ✅ Found Log Analytics: $($logAnalytics.name)" -ForegroundColor Green

$actionGroup = az monitor action-group list --resource-group $ResourceGroupName --query "[0]" --output json | ConvertFrom-Json
if (-not $actionGroup) {
    Write-Host "   ❌ No Action Group found in $ResourceGroupName" -ForegroundColor Red
    exit 1
}
Write-Host "   ✅ Found Action Group: $($actionGroup.name)" -ForegroundColor Green

# Get location from resource group
$rg = az group show --name $ResourceGroupName --output json | ConvertFrom-Json
$location = $rg.location
Write-Host "   ✅ Location: $location" -ForegroundColor Green

# Deploy Bicep template
Write-Host ""
Write-Host "🚀 Deploying VM infrastructure..." -ForegroundColor Yellow

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$bicepPath = Join-Path $scriptPath "vm-infra.bicep"

$deployment = az deployment group create `
    --resource-group $ResourceGroupName `
    --template-file $bicepPath `
    --parameters vmName=$VmName `
                 adminUsername=$AdminUsername `
                 adminPassword=$plainPassword `
                 logAnalyticsWorkspaceId=$($logAnalytics.id) `
                 actionGroupId=$($actionGroup.id) `
                 location=$location `
    --output json | ConvertFrom-Json

if ($LASTEXITCODE -ne 0) {
    Write-Host "   ❌ Deployment failed!" -ForegroundColor Red
    exit 1
}

Write-Host "   ✅ VM deployed successfully!" -ForegroundColor Green

# Get outputs
$vmPublicIp = $deployment.properties.outputs.vmPublicIp.value
$vmPrivateIp = $deployment.properties.outputs.vmPrivateIp.value

Write-Host ""
Write-Host "╔═══════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║                    Deployment Complete! 🎉                        ║" -ForegroundColor Green
Write-Host "╚═══════════════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "📋 VM Details:" -ForegroundColor Cyan
Write-Host "   VM Name:       $VmName" -ForegroundColor White
Write-Host "   Public IP:     $vmPublicIp" -ForegroundColor White
Write-Host "   Private IP:    $vmPrivateIp" -ForegroundColor White
Write-Host "   Username:      $AdminUsername" -ForegroundColor White
Write-Host ""
Write-Host "🔗 Connect via RDP:" -ForegroundColor Cyan
Write-Host "   mstsc /v:$vmPublicIp" -ForegroundColor Yellow
Write-Host ""
Write-Host "📋 Next Steps:" -ForegroundColor Cyan
Write-Host "   1. Wait ~5 minutes for Azure Monitor Agent to initialize" -ForegroundColor White
Write-Host "   2. Run: .\trigger-cpu-spike.ps1 -Action start" -ForegroundColor White
Write-Host "   3. Watch alert fire in Azure Monitor (~5 min)" -ForegroundColor White
Write-Host "   4. SRE Agent investigates and kills the process" -ForegroundColor White
Write-Host ""
