<#
.SYNOPSIS
    Triggers or stops a CPU spike on the demo VM.

.DESCRIPTION
    This script connects to the VM and runs a PowerShell process that consumes ~90% CPU.
    The Azure SRE Agent should detect this via the CPU alert and suggest killing the process.

.PARAMETER Action
    The action to perform: 'start' to trigger CPU spike, 'stop' to kill the process, 'status' to check.

.PARAMETER VmName
    Name of the VM (default: sre-demo-vm).

.PARAMETER ResourceGroupName
    Name of the resource group (default: rg-sre-demo-india).

.EXAMPLE
    # Start CPU spike
    .\trigger-cpu-spike.ps1 -Action start

    # Stop CPU spike (manually - SRE Agent should do this)
    .\trigger-cpu-spike.ps1 -Action stop

    # Check status
    .\trigger-cpu-spike.ps1 -Action status
#>

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("start", "stop", "status")]
    [string]$Action,
    
    [Parameter(Mandatory = $false)]
    [string]$VmName = "sre-demo-vm",
    
    [Parameter(Mandatory = $false)]
    [string]$ResourceGroupName = "rg-sre-demo-india"
)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "╔═══════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║         Azure SRE Agent Demo - VM CPU Spike Trigger               ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Check if VM exists
Write-Host "🔍 Finding VM..." -ForegroundColor Yellow
$vm = az vm show --name $VmName --resource-group $ResourceGroupName --output json 2>$null | ConvertFrom-Json
if (-not $vm) {
    Write-Host "   ❌ VM '$VmName' not found in resource group '$ResourceGroupName'" -ForegroundColor Red
    exit 1
}
Write-Host "   ✅ Found VM: $VmName" -ForegroundColor Green

# CPU stress script - Uses Start-Process for persistent background processes
$cpuStressScript = @'
# CPU Stress - Persistent Process-Based Load
Write-Host "Starting persistent CPU stress processes..." -ForegroundColor Yellow

$cpuCores = (Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors
Write-Host "CPU Cores: $cpuCores"
Write-Host "Launching $cpuCores background PowerShell processes..."

# Create script file for CPU burn
$burnScript = @"
`$result = 1
while (`$true) {
    `$result = `$result + 1
    `$result = `$result * 2  
    `$result = `$result - 1
    `$result = `$result / 2
    if (`$result -gt 1000000) { `$result = 1 }
}
"@

$scriptPath = "C:\CPUStress.ps1"
$burnScript | Out-File -FilePath $scriptPath -Force

# Create marker file
"running" | Out-File -FilePath "C:\HighCpuProcess.marker" -Force

# Launch actual PowerShell processes (not jobs) - these will persist
for ($i = 1; $i -le $cpuCores; $i++) {
    Start-Process powershell.exe -ArgumentList "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`"" -WindowStyle Hidden
}

Start-Sleep -Seconds 2
$cpuProcesses = Get-Process powershell | Where-Object {$_.Path -like "*PowerShell*"}
Write-Host "Started $($cpuProcesses.Count) PowerShell processes burning CPU" -ForegroundColor Green
Write-Host "CPU will sustain at 90%+ until processes are killed" -ForegroundColor Green
Write-Host ""
Write-Host "Process IDs: $($cpuProcesses.Id -join ', ')"
'@

$stopCpuScript = @'
Write-Host "Stopping CPU stress processes..." -ForegroundColor Yellow

# Kill all PowerShell processes running CPUStress.ps1
$stressProcesses = Get-WmiObject Win32_Process | Where-Object { $_.CommandLine -like "*CPUStress.ps1*" }
if ($stressProcesses) {
    foreach ($proc in $stressProcesses) {
        Write-Host "Killing process $($proc.ProcessId)..."
        Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue
    }
    Write-Host "Killed $($stressProcesses.Count) stress processes"
}

# Also kill any high-CPU PowerShell processes as backup
$highCpuProcs = Get-Process powershell -ErrorAction SilentlyContinue | Where-Object { $_.CPU -gt 30 -and $_.Id -ne $PID }
if ($highCpuProcs) {
    $highCpuProcs | Stop-Process -Force -ErrorAction SilentlyContinue
    Write-Host "Killed $($highCpuProcs.Count) high-CPU PowerShell processes"
}

# Clean up files
Remove-Item "C:\CPUStress.ps1" -Force -ErrorAction SilentlyContinue
Remove-Item "C:\HighCpuProcess.marker" -Force -ErrorAction SilentlyContinue
Remove-Item "C:\stress.ps1" -Force -ErrorAction SilentlyContinue

# Also clean up any scheduled task from previous approach
schtasks /delete /tn CpuStress /f 2>$null

Write-Host "CPU stress stopped and cleaned up." -ForegroundColor Green
'@

$statusScript = @'
Write-Host "CPU Status Check" -ForegroundColor Cyan
Write-Host "================" -ForegroundColor Cyan

# Get CPU usage
$cpu = (Get-Counter "\Processor(_Total)\% Processor Time" -SampleInterval 2 -MaxSamples 3 | Select-Object -ExpandProperty CounterSamples | Measure-Object -Property CookedValue -Average).Average
Write-Host "Current CPU Usage: $([math]::Round($cpu, 1))%"

# Check for stress processes
$stressProcs = Get-WmiObject Win32_Process | Where-Object { $_.CommandLine -like "*CPUStress.ps1*" }
if ($stressProcs) {
    Write-Host "CPU stress processes running: $($stressProcs.Count)" -ForegroundColor Yellow
    Write-Host "Process IDs: $($stressProcs.ProcessId -join ', ')"
} else {
    Write-Host "No CPU stress processes detected" -ForegroundColor Green
}

# Check marker file
if (Test-Path "C:\HighCpuProcess.marker") {
    Write-Host "Marker file: Present (stress test active)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Top 5 processes by CPU:"
Get-Process | Sort-Object CPU -Descending | Select-Object -First 5 Name, CPU, Id | Format-Table -AutoSize
'@

switch ($Action) {
    "status" {
        Write-Host "[STATUS] Checking VM CPU status..." -ForegroundColor Yellow
        Write-Host ""
        
        # Use encoded command for reliable execution
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($statusScript))
        $result = az vm run-command invoke `
            --resource-group $ResourceGroupName `
            --name $VmName `
            --command-id RunPowerShellScript `
            --scripts "powershell -EncodedCommand $encoded" `
            --output json | ConvertFrom-Json
        
        Write-Host $result.value[0].message -ForegroundColor White
    }
    
    "start" {
        Write-Host "[TRIGGER] TRIGGERING INCIDENT: Starting CPU stress on VM..." -ForegroundColor Red
        Write-Host "   This will consume ~100% CPU and trigger the alert." -ForegroundColor Yellow
        Write-Host ""
        
        # Use encoded command for reliable execution
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cpuStressScript))
        $result = az vm run-command invoke `
            --resource-group $ResourceGroupName `
            --name $VmName `
            --command-id RunPowerShellScript `
            --scripts "powershell -EncodedCommand $encoded" `
            --output json | ConvertFrom-Json
        
        Write-Host $result.value[0].message -ForegroundColor White
        
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Green
        Write-Host "  CPU STRESS STARTED" -ForegroundColor Green
        Write-Host "========================================" -ForegroundColor Green
        Write-Host ""
        
        Write-Host "CPU Load Status:" -ForegroundColor Cyan
        Write-Host "   Background processes launched"
        Write-Host "   Expected CPU usage: 90-100%"
        Write-Host "   Duration: Until stopped manually or by SRE Agent"
        Write-Host ""
        
        Write-Host "Timeline:" -ForegroundColor Yellow
        Write-Host "   [Now] CPU load processes started"
        Write-Host "   [+2 min] CPU usage visible in Azure Portal"
        Write-Host "   [+5 min] Alert evaluation window completes"
        Write-Host "   [+7 min] Alert fires: 'VM CPU exceeds 85%'"
        Write-Host "   [+10 min] Incident appears in SRE Agent"
        Write-Host ""
        
        Write-Host "NEXT STEPS:" -ForegroundColor Yellow
        Write-Host "   1. Run: .\trigger-cpu-spike.ps1 -Action status"
        Write-Host "   2. Wait 5-7 minutes for alert to fire"
        Write-Host "   3. Check Azure Portal -> Alerts"
        Write-Host "   4. Check Azure SRE Agent -> Incidents"
        Write-Host "   5. Review SRE Agent recommendations"
        Write-Host "   6. Run: .\trigger-cpu-spike.ps1 -Action stop (or let SRE Agent fix it)"
        Write-Host ""
        
        Write-Host "Azure Portal Links:" -ForegroundColor Cyan
        Write-Host "   Alerts: https://portal.azure.com/#blade/Microsoft_Azure_Monitoring/AzureMonitoringBrowseBlade/alertsV2" -ForegroundColor Blue
        Write-Host "   SRE Agent: https://aka.ms/sreagent/portal" -ForegroundColor Blue
        Write-Host ""
    }
    
    "stop" {
        Write-Host "[RESOLVE] RESOLVING INCIDENT: Stopping CPU stress..." -ForegroundColor Green
        Write-Host "   Note: Azure SRE Agent should normally do this." -ForegroundColor Yellow
        Write-Host ""
        
        # Use encoded command for reliable execution
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($stopCpuScript))
        $result = az vm run-command invoke `
            --resource-group $ResourceGroupName `
            --name $VmName `
            --command-id RunPowerShellScript `
            --scripts "powershell -EncodedCommand $encoded" `
            --output json | ConvertFrom-Json
        
        Write-Host $result.value[0].message -ForegroundColor White
        
        Write-Host ""
        Write-Host "=======================================================================" -ForegroundColor Green
        Write-Host "                      INCIDENT RESOLVED                               " -ForegroundColor Green
        Write-Host "=======================================================================" -ForegroundColor Green
        Write-Host ""
        Write-Host "   CPU stress process has been terminated." -ForegroundColor White
        Write-Host "   Alert should auto-resolve within 5 minutes." -ForegroundColor Yellow
    }
}

Write-Host ""
