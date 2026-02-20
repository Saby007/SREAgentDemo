<#
.SYNOPSIS
    Deploys the Azure SRE Agent Demo infrastructure and web application.

.DESCRIPTION
    This script deploys:
    - Azure Web App (with Angular frontend + Node.js backend)
    - Azure SQL Server (serverless tier)
    - Azure SQL Database with sample data
    - Azure Monitor alerts for Web App health
    - Log Analytics Workspace

.PARAMETER ResourceGroupName
    Name of the resource group to create/use.

.PARAMETER Location
    Azure region for deployment (default: eastus2).

.EXAMPLE
    .\deploy.ps1 -ResourceGroupName "rg-sre-demo"
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$ResourceGroupName = "rg-sre-demo",
    
    [Parameter(Mandatory = $false)]
    [string]$Location = "eastus2"
)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "╔═══════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║         Azure SRE Agent Demo - Infrastructure Deployment          ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Check Azure CLI is installed
Write-Host "🔍 Checking prerequisites..." -ForegroundColor Yellow
try {
    $azVersion = az version --output json | ConvertFrom-Json
    Write-Host "   ✅ Azure CLI version: $($azVersion.'azure-cli')" -ForegroundColor Green
} catch {
    Write-Host "   ❌ Azure CLI not found. Please install it from https://aka.ms/installazurecli" -ForegroundColor Red
    exit 1
}

# Check if logged in
Write-Host "🔐 Checking Azure login..." -ForegroundColor Yellow
$account = az account show --output json 2>$null | ConvertFrom-Json
if (-not $account) {
    Write-Host "   📝 Please log in to Azure..." -ForegroundColor Yellow
    az login
    $account = az account show --output json | ConvertFrom-Json
}
Write-Host "   ✅ Logged in as: $($account.user.name)" -ForegroundColor Green
Write-Host "   📋 Subscription: $($account.name)" -ForegroundColor Green

# Get current user's Azure AD info
Write-Host ""
Write-Host "🔐 Getting Azure AD identity..." -ForegroundColor Yellow
$aadUser = az ad signed-in-user show --output json | ConvertFrom-Json
$aadObjectId = $aadUser.id
$aadLogin = $account.user.name
Write-Host "   ✅ Azure AD User: $aadLogin" -ForegroundColor Green
Write-Host "   ✅ Object ID: $aadObjectId" -ForegroundColor Green

# Get current IP for firewall rule
Write-Host ""
Write-Host "🌐 Getting your IP address for firewall rule..." -ForegroundColor Yellow
try {
    $myIp = (Invoke-RestMethod -Uri "https://api.ipify.org" -TimeoutSec 5)
    Write-Host "   ✅ Your IP: $myIp" -ForegroundColor Green
} catch {
    $myIp = ""
    Write-Host "   ⚠️  Could not detect IP, skipping firewall rule" -ForegroundColor Yellow
}

# Create Resource Group
Write-Host ""
Write-Host "📦 Creating resource group '$ResourceGroupName'..." -ForegroundColor Yellow
az group create --name $ResourceGroupName --location $Location --output none
Write-Host "   ✅ Resource group created/verified" -ForegroundColor Green

# Deploy Bicep template
Write-Host ""
Write-Host "🚀 Deploying infrastructure (this may take 5-10 minutes)..." -ForegroundColor Yellow

$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$bicepPath = Join-Path $scriptPath "..\infra\main.bicep"

# Create a temporary parameters file
$paramsContent = @"
{
  "`$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "location": { "value": "$Location" },
    "baseName": { "value": "sre-demo" },
    "aadAdminObjectId": { "value": "$aadObjectId" },
    "aadAdminLogin": { "value": "$aadLogin" },
    "allowedIpAddress": { "value": "$myIp" }
  }
}
"@

$paramsFile = Join-Path $scriptPath "deploy-params.json"
$paramsContent | Out-File -FilePath $paramsFile -Encoding utf8

$deployment = az deployment group create `
    --resource-group $ResourceGroupName `
    --template-file $bicepPath `
    --parameters "@$paramsFile" `
    --output json | ConvertFrom-Json

# Clean up params file
Remove-Item $paramsFile -Force -ErrorAction SilentlyContinue

if ($LASTEXITCODE -ne 0) {
    Write-Host "   ❌ Deployment failed!" -ForegroundColor Red
    exit 1
}

Write-Host "   ✅ Infrastructure deployed successfully!" -ForegroundColor Green

# Get outputs
$outputs = $deployment.properties.outputs
$sqlServerFqdn = $outputs.sqlServerFqdn.value
$sqlServerName = $outputs.sqlServerName.value
$sqlDatabaseName = $outputs.sqlDatabaseName.value
$webAppName = $outputs.webAppName.value
$webAppUrl = $outputs.webAppUrl.value
$webAppPrincipalId = $outputs.webAppPrincipalId.value
$resourceGroup = $outputs.resourceGroupName.value

# Create SQL initialization script
Write-Host ""
Write-Host "📊 Creating database initialization script..." -ForegroundColor Yellow

$initSql = @"
-- ============================================================
-- Azure SRE Agent Demo - Database Initialization Script
-- Run this in Azure Portal > SQL Database > Query Editor
-- ============================================================

-- Create Products table
IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='Products' AND xtype='U')
CREATE TABLE Products (
    id INT PRIMARY KEY IDENTITY(1,1),
    name NVARCHAR(100) NOT NULL,
    description NVARCHAR(500),
    price DECIMAL(10,2) NOT NULL,
    category NVARCHAR(50),
    stock INT DEFAULT 0
);
GO

-- Insert sample data
IF NOT EXISTS (SELECT * FROM Products)
BEGIN
    INSERT INTO Products (name, description, price, category, stock) VALUES
    ('Laptop Pro 15', 'High-performance laptop with 15-inch display', 1299.99, 'Electronics', 45),
    ('Wireless Mouse', 'Ergonomic wireless mouse with long battery life', 29.99, 'Electronics', 150),
    ('USB-C Hub', '7-in-1 USB-C hub with HDMI and SD card reader', 49.99, 'Electronics', 80),
    ('Mechanical Keyboard', 'RGB mechanical keyboard with Cherry MX switches', 129.99, 'Electronics', 60),
    ('Monitor 27"', '4K IPS monitor with HDR support', 399.99, 'Electronics', 25),
    ('Webcam HD', '1080p webcam with built-in microphone', 79.99, 'Electronics', 100),
    ('Headphones Pro', 'Noise-canceling wireless headphones', 249.99, 'Audio', 35),
    ('Bluetooth Speaker', 'Portable waterproof Bluetooth speaker', 59.99, 'Audio', 90),
    ('Standing Desk', 'Electric height-adjustable standing desk', 549.99, 'Furniture', 15),
    ('Office Chair', 'Ergonomic office chair with lumbar support', 299.99, 'Furniture', 20),
    ('Desk Lamp', 'LED desk lamp with adjustable brightness', 39.99, 'Furniture', 75),
    ('Cable Management Kit', 'Complete cable management solution', 24.99, 'Accessories', 200);
END
GO

-- Grant access to Web App managed identity
-- NOTE: Replace $webAppName with actual web app name if different
IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = '$webAppName')
BEGIN
    CREATE USER [$webAppName] FROM EXTERNAL PROVIDER;
    ALTER ROLE db_datareader ADD MEMBER [$webAppName];
    ALTER ROLE db_datawriter ADD MEMBER [$webAppName];
    PRINT 'Web App identity granted access successfully';
END
ELSE
BEGIN
    PRINT 'Web App identity already has access';
END
GO

-- Verify setup
SELECT 'Products count: ' + CAST(COUNT(*) AS VARCHAR) FROM Products;
SELECT 'Database users: ' + name FROM sys.database_principals WHERE type = 'E';
"@

$initSqlPath = Join-Path $scriptPath "init-database.sql"
$initSql | Out-File -FilePath $initSqlPath -Encoding utf8
Write-Host "   ✅ SQL Script saved to: scripts/init-database.sql" -ForegroundColor Green

# Deploy Web App code
Write-Host ""
Write-Host "📦 Deploying web application to Azure..." -ForegroundColor Yellow

$webappPath = Join-Path $scriptPath "..\webapp"

# Create deployment package
$zipPath = Join-Path $scriptPath "webapp.zip"
if (Test-Path $zipPath) {
    Remove-Item $zipPath -Force
}

# Compress webapp folder
Compress-Archive -Path "$webappPath\*" -DestinationPath $zipPath -Force

# Deploy to Azure Web App
az webapp deployment source config-zip `
    --resource-group $ResourceGroupName `
    --name $webAppName `
    --src $zipPath `
    --output none 2>$null

if ($LASTEXITCODE -eq 0) {
    Write-Host "   ✅ Web application deployed!" -ForegroundColor Green
} else {
    Write-Host "   ⚠️  Web app deployment may need retry. Trying again..." -ForegroundColor Yellow
    Start-Sleep -Seconds 5
    az webapp deployment source config-zip `
        --resource-group $ResourceGroupName `
        --name $webAppName `
        --src $zipPath `
        --output none
}

# Clean up zip
Remove-Item $zipPath -Force -ErrorAction SilentlyContinue

# Summary
Write-Host ""
Write-Host "╔═══════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║                    Deployment Complete! 🎉                        ║" -ForegroundColor Green
Write-Host "╚═══════════════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "📋 Resource Details:" -ForegroundColor Cyan
Write-Host "   Resource Group:  $ResourceGroupName" -ForegroundColor White
Write-Host "   SQL Server:      $sqlServerFqdn" -ForegroundColor White
Write-Host "   Database:        $sqlDatabaseName" -ForegroundColor White
Write-Host "   Web App:         $webAppName" -ForegroundColor White
Write-Host "   Web App URL:     $webAppUrl" -ForegroundColor Yellow
Write-Host ""
Write-Host "╔═══════════════════════════════════════════════════════════════════╗" -ForegroundColor Red
Write-Host "║  ⚠️  IMPORTANT - Complete these steps to finish setup:            ║" -ForegroundColor Red
Write-Host "╚═══════════════════════════════════════════════════════════════════╝" -ForegroundColor Red
Write-Host ""
Write-Host "   STEP 1: Initialize the database" -ForegroundColor White
Write-Host "   ─────────────────────────────────" -ForegroundColor Gray
Write-Host "   a) Open Azure Portal: https://portal.azure.com" -ForegroundColor Yellow
Write-Host "   b) Go to: SQL databases > $sqlDatabaseName > Query editor" -ForegroundColor Yellow
Write-Host "   c) Login with: Azure AD - $aadLogin" -ForegroundColor Yellow
Write-Host "   d) Copy & run the script from: scripts/init-database.sql" -ForegroundColor Yellow
Write-Host ""
Write-Host "   STEP 2: Configure Azure SRE Agent" -ForegroundColor White
Write-Host "   ──────────────────────────────────" -ForegroundColor Gray
Write-Host "   a) Open: https://aka.ms/sreagent/portal" -ForegroundColor Yellow
Write-Host "   b) Click 'Create' to create a new SRE Agent" -ForegroundColor Yellow
Write-Host "   c) Select resource group: $ResourceGroupName" -ForegroundColor Yellow
Write-Host "   d) Region: East US 2" -ForegroundColor Yellow
Write-Host ""
Write-Host "   STEP 3: Test the application" -ForegroundColor White
Write-Host "   ─────────────────────────────" -ForegroundColor Gray
Write-Host "   Open: $webAppUrl" -ForegroundColor Yellow
Write-Host ""
Write-Host "   STEP 4: Trigger the incident (for demo)" -ForegroundColor White
Write-Host "   ─────────────────────────────────────────" -ForegroundColor Gray
Write-Host "   Run: .\trigger-incident.ps1 -Action pause" -ForegroundColor Yellow
Write-Host ""
