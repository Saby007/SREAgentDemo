# Azure SRE Agent - VM CPU Spike Scenario

## Overview

This scenario demonstrates Azure SRE Agent's ability to:
1. Detect high CPU usage on a Windows VM
2. Identify the process causing the issue
3. Automatically remediate by killing the runaway process

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     rg-sre-demo-india                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────┐     ┌──────────────────┐                     │
│  │   VM         │────▶│  Azure Monitor   │                     │
│  │ (CPU Spike)  │     │  Agent (AMA)     │                     │
│  └──────────────┘     └────────┬─────────┘                     │
│                                │                                │
│                                ▼                                │
│                    ┌───────────────────────┐                   │
│                    │  Log Analytics        │                   │
│                    │  (Performance Data)   │                   │
│                    └───────────┬───────────┘                   │
│                                │                                │
│                                ▼                                │
│                    ┌───────────────────────┐                   │
│                    │  Metric Alert         │                   │
│                    │  (CPU > 85%, Sev 2)   │                   │
│                    └───────────┬───────────┘                   │
│                                │                                │
└────────────────────────────────┼────────────────────────────────┘
                                 │
                                 ▼
                    ┌───────────────────────┐
                    │   Azure SRE Agent     │
                    │   (East US 2)         │
                    │                       │
                    │  1. Receive alert     │
                    │  2. Query perf data   │
                    │  3. Identify process  │
                    │  4. Kill process      │
                    └───────────────────────┘
```

## Deployment

### Step 1: Deploy the VM

```powershell
cd scenario-vm-cpu
.\deploy-vm.ps1 -AdminPassword (ConvertTo-SecureString "YourSecureP@ss123!" -AsPlainText -Force)
```

### Step 2: Wait for Azure Monitor Agent

The Azure Monitor Agent takes ~5 minutes to initialize and start collecting data.

### Step 3: Configure SRE Agent Incident Response Plan

See [SRE Agent Instructions](#sre-agent-incident-response-plan-instructions) below.

## Usage

### Trigger CPU Spike (Start Incident)

```powershell
.\trigger-cpu-spike.ps1 -Action start
```

### Check Status

```powershell
.\trigger-cpu-spike.ps1 -Action status
```

### Manually Stop (if SRE Agent doesn't)

```powershell
.\trigger-cpu-spike.ps1 -Action stop
```

## Alert Configuration

| Setting | Value |
|---------|-------|
| **Alert Name** | sre-demo-vm-cpu-alert |
| **Metric** | Percentage CPU |
| **Threshold** | > 85% |
| **Severity** | 2 (Warning) |
| **Evaluation Frequency** | 1 minute |
| **Window Size** | 5 minutes |

---

## SRE Agent Incident Response Plan Instructions

### Create a New Incident Response Plan

1. Go to Azure SRE Agent Portal: https://aka.ms/sreagent/portal
2. Navigate to **Incident management** → **Create incident response plan**
3. Configure as follows:

### Filters

| Filter | Value |
|--------|-------|
| **Incident type** | Default |
| **Impacted service** | Virtual Machines |
| **Priority** | Sev 2 (Warning) |
| **Title contains** | `CPU` or `cpu` |

### Autonomy Level

| Setting | Value |
|---------|-------|
| **Mode** | Review (for demo) or Autonomous (for production) |

### Custom Instructions

Copy and paste the following instructions:

```
You are investigating a high CPU alert on a Windows Virtual Machine.

INVESTIGATION METHODOLOGY:
1. Connect to the VM and query current CPU usage
2. Identify which process is consuming the most CPU
3. Determine if the process is legitimate or a runaway/malicious process
4. Take appropriate action based on findings

DIAGNOSTIC STEPS:
1. Use Azure VM Run Command to execute diagnostic scripts on the VM
2. Query the top CPU-consuming processes using:
   - Get-Process | Sort-Object CPU -Descending | Select-Object -First 10 Name, CPU, Id
3. Check for known runaway process indicators:
   - Process name contains "HighCpuProcess" → This is a test stress process, safe to kill
   - PowerShell process with unusually high CPU → Likely a stress script, investigate further
   - Unknown process consuming >50% CPU → Potential runaway, gather more info before killing

IDENTIFICATION CRITERIA:
- If process name is "HighCpuProcess" → CONFIRMED runaway test process
- If process is "powershell" with CPU > 80 seconds → LIKELY stress script
- If multiple PowerShell background jobs named "HighCpuProcess-*" exist → CONFIRMED stress test

REMEDIATION ACTIONS:
When you identify a runaway process, use Azure VM Run Command to kill it:

For PowerShell stress jobs:
```powershell
Get-Job -Name "HighCpuProcess*" | Stop-Job | Remove-Job -Force
```

For high-CPU PowerShell processes:
```powershell
Get-Process -Name "powershell*" | Where-Object { $_.CPU -gt 60 } | Stop-Process -Force
```

General process termination (use process ID from investigation):
```powershell
Stop-Process -Id <ProcessId> -Force
```

VALIDATION:
After remediation, verify CPU has returned to normal:
```powershell
$cpu = (Get-Counter '\Processor(_Total)\% Processor Time' -SampleInterval 2 -MaxSamples 3 | 
    Select-Object -ExpandProperty CounterSamples | 
    Measure-Object -Property CookedValue -Average).Average
Write-Host "Current CPU: $([math]::Round($cpu, 1))%"
```

ESCALATION:
- If CPU remains high after killing identified processes, escalate to human operator
- If process is a critical system process, do NOT kill - escalate instead
- If unable to connect to VM, check VM health and network connectivity first
```

### Tools to Enable

Ensure these tools are available to the agent:
- ✅ Azure CLI (az vm run-command)
- ✅ Azure Monitor (metrics query)
- ✅ Log Analytics (Kusto query)

---

## Demo Flow

1. **Trigger Incident**
   ```powershell
   .\trigger-cpu-spike.ps1 -Action start
   ```

2. **Wait for Alert** (~5 minutes)
   - CPU spikes to ~90%
   - Alert fires when CPU > 85% for 5 minutes

3. **SRE Agent Investigation**
   - Agent receives alert
   - Queries VM CPU metrics
   - Identifies "HighCpuProcess" jobs

4. **SRE Agent Remediation**
   - Proposes: "Kill the HighCpuProcess jobs"
   - You approve (in Review mode)
   - Agent executes kill command

5. **Validation**
   - CPU returns to normal
   - Alert auto-resolves
   - Incident closed

---

## Manual Chat Prompts for Demo

If alerts aren't auto-picked up, use these chat prompts:

```
My VM sre-demo-vm has high CPU usage. Can you investigate what process is causing it?
```

```
Investigate the high CPU alert on sre-demo-vm and identify the runaway process.
```

```
Kill the process causing high CPU on sre-demo-vm.
```

---

## Cleanup

To remove the VM and associated resources:

```powershell
az vm delete --name sre-demo-vm --resource-group rg-sre-demo-india --yes
az network nic delete --name sre-demo-vm-nic --resource-group rg-sre-demo-india
az network public-ip delete --name sre-demo-vm-pip --resource-group rg-sre-demo-india
az network vnet delete --name sre-demo-vm-vnet --resource-group rg-sre-demo-india
az network nsg delete --name sre-demo-vm-nsg --resource-group rg-sre-demo-india
az monitor metrics alert delete --name sre-demo-vm-cpu-alert --resource-group rg-sre-demo-india
```
