# Reactive Incident Response with Azure SRE Agent: From Alert to Resolution in Minutes

## When things break at 2 AM, your AI teammate is already investigating.

![Hero Image: SRE Agent Dashboard showing active incidents](images/hero-sre-agent-dashboard.png)
*[SCREENSHOT: SRE Agent portal overview with incident list]*

---

## The Reactive Incident Challenge

Your monitoring is solid. Alerts fire when they should. But then what?

- Alert lands in Teams/PagerDuty
- On-call engineer wakes up, logs in
- Starts investigating: "What's broken? Why? How do I fix it?"
- 20 minutes later, they're still gathering context

The alert was fast. The human response? Not so much.

### The Traditional Incident Response Flow

```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│   Alert     │───▶│   Human     │───▶│  Manual     │───▶│ Resolution  │
│   Fires     │    │ Acknowledges│    │Investigation│    │  (Maybe)    │
│             │    │  (5-15 min) │    │  (15-30 min)│    │             │
└─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘
     t=0              t=5-15min         t=20-45min         t=30-60min
```

### The SRE Agent Flow

```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│   Alert     │───▶│ SRE Agent   │───▶│    AI       │───▶│  Human      │
│   Fires     │    │ Acknowledges│    │Investigation│    │  Approves   │
│             │    │  (Instant)  │    │  (2-10 min) │    │             │
└─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘
     t=0              t=0               t=2-10min          t=10-15min
```

**What if the investigation started the moment the alert fired?**

That's exactly what Azure SRE Agent does. It doesn't wait for humans to acknowledge—it starts investigating immediately, gathering context, identifying root causes, and preparing remediation options.

I tested this with two real-world scenarios: a database connectivity outage and a VM CPU spike. Here's what happened.

---

## Two Real-World Incidents

| Scenario | Trigger | Root Cause | Resolution |
|----------|---------|------------|------------|
| **Web App Health Failure** | Sev1 Alert - Health check failing | SQL Server public access disabled | Enabled public access + firewall rule |
| **VM High CPU** | Sev2 Alert - CPU > 85% for 5 mins | Runaway PowerShell processes | Identified and killed processes |

Both incidents were detected, diagnosed, and remediated by SRE Agent with minimal human intervention—just approval clicks.

---

## Incident 1: Azure SQL Database Connectivity Outage

### The Alert

![SQL Alert in Azure Monitor](images/incident1-alert-fired.png)
*[SCREENSHOT: Azure Monitor alert showing Sev1 health check failure]*

```
🔴 Sev1 Alert Fired
Alert Rule: sre-demo-webapp-health-alert
Description: Alert when Web App health check fails - indicates backend/database connectivity issues
Resource: sre-demo-app-6o26gsgynw436
Time: 02/04/2026 07:59:35 UTC
```

### Alert Configuration Details

The alert was configured using Azure Monitor metric alerts:

```bicep
resource webAppHealthAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'sre-demo-webapp-health-alert'
  properties: {
    severity: 1
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'HealthCheckStatus'
          metricName: 'HealthCheckStatus'
          operator: 'LessThan'
          threshold: 100
          timeAggregation: 'Average'
        }
      ]
    }
    targetResourceType: 'Microsoft.Web/sites'
    targetResourceRegion: 'centralindia'
  }
}
```

### What SRE Agent Did (Autonomously)

![SRE Agent Investigation Flow](images/incident1-investigation-flow.png)
*[SCREENSHOT: SRE Agent chat showing the investigation steps and thinking process]*

The moment the alert fired, SRE Agent acknowledged and began investigating:

**1. Symptom Assessment**
- Pulled web app ARM configuration (AlwaysOn, Basic plan, system-assigned identity)
- Analyzed HTTP 5xx and request metrics over 2 hours
- Observed intermittent traffic spikes indicating service impact

```kusto
// KQL query SRE Agent ran against Application Insights
requests
| where timestamp > ago(2h)
| summarize 
    TotalRequests = count(),
    FailedRequests = countif(resultCode >= 500),
    FailureRate = round(100.0 * countif(resultCode >= 500) / count(), 2)
| project TotalRequests, FailedRequests, FailureRate
```

**2. Dependency Mapping**

![Application Insights Dependencies](images/incident1-app-insights-dependencies.png)
*[SCREENSHOT: Application Insights showing SQL dependency failures at 100%]*

- Queried Application Insights to identify failing backends
- Found: `sre-demo-sql-6o26gsgynw436.database.windows.net` failing **100% (80/80 calls)** in last 30 minutes
- Result code: `503` on "SQL Health Check" and "GetProducts" operations

```kusto
// Dependency failure analysis
dependencies
| where timestamp > ago(30m)
| where target contains "database.windows.net"
| summarize 
    TotalCalls = count(),
    FailedCalls = countif(success == false),
    FailureRate = round(100.0 * countif(success == false) / count(), 2)
| project TotalCalls, FailedCalls, FailureRate
```

**3. Network Validation**
- Tested DNS resolution from web app to SQL endpoint ✅ Success
- Tested TCP reachability on port 1433 ✅ Success
- Conclusion: Network path is healthy; issue is at access/auth layer

```bash
# SRE Agent validated network connectivity using:
# DNS Resolution Test
nslookup sre-demo-sql-6o26gsgynw436.database.windows.net

# TCP Port Test (from App Service)
tcpping sre-demo-sql-6o26gsgynw436.database.windows.net:1433
```

**4. Configuration Analysis**

![SQL Server Configuration](images/incident1-sql-config.png)
*[SCREENSHOT: Azure CLI output showing publicNetworkAccess: Disabled]*

```bash
# SRE Agent queried SQL server configuration
az sql server show -g rg-sre-demo-india -n sre-demo-sql-6o26gsgynw436 \
  --query "{publicNetworkAccess:publicNetworkAccess, fullyQualifiedDomainName:fullyQualifiedDomainName}"

# Output:
{
  "publicNetworkAccess": "Disabled",  # 🔴 ROOT CAUSE
  "fullyQualifiedDomainName": "sre-demo-sql-6o26gsgynw436.database.windows.net"
}
```

- Discovered: **Azure SQL public network access = Disabled**
- Web app has no VNet integration or Private Endpoint
- Root cause identified: Access model mismatch

### The Root Cause Analysis

![RCA Output in SRE Agent](images/incident1-rca-output.png)
*[SCREENSHOT: SRE Agent displaying the root cause analysis summary]*

> **Root cause: Azure SQL public network access is Disabled while the web app has no VNet integration/private endpoint, so the app cannot reach SQL at the access model layer.**

SRE Agent presented two remediation options:

| Option | Approach | Speed | Security | Use Case |
|--------|----------|-------|----------|----------|
| **A** | Enable public access + Allow Azure Services (0.0.0.0) | ⚡ Fast | 🟡 Moderate | Quick restore, non-prod |
| **B** | Add web app's specific outbound IPs to firewall | 🐢 Slower | 🟢 Stricter | Production environments |
| **C** | Configure Private Endpoint + VNet Integration | 🐢🐢 Slowest | 🟢🟢 Best | Long-term solution |

### Remediation (With Approval)

![Remediation Approval](images/incident1-remediation-approval.png)
*[SCREENSHOT: SRE Agent asking for approval before executing remediation]*

I approved Option A for rapid restoration. SRE Agent executed:

```bash
# Step 1: Enable public network access
az sql server update -g rg-sre-demo-india -n sre-demo-sql-6o26gsgynw436 \
  --subscription 616dc9b8-b4aa-415f-8dcb-71bc462916c5 \
  --set publicNetworkAccess=Enabled

# Step 2: Add Azure Services firewall rule
az sql server firewall-rule create \
  -g rg-sre-demo-india \
  -s sre-demo-sql-6o26gsgynw436 \
  -n AllowAzureServices \
  --subscription 616dc9b8-b4aa-415f-8dcb-71bc462916c5 \
  --start-ip-address 0.0.0.0 \
  --end-ip-address 0.0.0.0
```

> ⚠️ **Security Note**: The `0.0.0.0` rule allows traffic from *any* Azure service, not just your web app. For production, use Option B (specific IPs) or Option C (Private Endpoint).

### Recovery Verified

![Recovery Verification](images/incident1-recovery-verified.png)
*[SCREENSHOT: SRE Agent showing successful recovery metrics]*

SRE Agent automatically verified recovery by re-querying Application Insights:

```kusto
// Post-remediation verification
dependencies
| where timestamp > ago(10m)
| where target contains "database.windows.net"
| summarize 
    TotalCalls = count(),
    SuccessfulCalls = countif(success == true),
    SuccessRate = round(100.0 * countif(success == true) / count(), 2)
```

Results:
- SQL dependencies: **65/65 successful** (100% success rate)
- HTTP 5xx errors: **Dropped to 0**
- Service restored ✅

### Timeline

| Time (UTC) | Event | Duration |
|------------|-------|----------|
| 07:59:35 | Alert fired | - |
| 07:59:36 | SRE Agent acknowledged | +1s |
| 08:00:00 | Started symptom assessment | +25s |
| 08:05:00 | Dependency mapping complete | +5m |
| 08:08:00 | Network validation complete | +3m |
| 08:10:00 | Root cause identified | +2m |
| 08:16:00 | Remediation approved | +6m (human) |
| 08:17:00 | Remediation executed | +1m |
| 08:20:00 | Recovery verified | +3m |

**Total time from alert to resolution: ~20 minutes** (6 minutes waiting for human approval)

---

## Incident 2: VM High CPU Spike

### The Alert

![VM CPU Alert](images/incident2-alert-fired.png)
*[SCREENSHOT: Azure Monitor showing VM CPU metric alert fired]*

```
🟡 Sev2 Alert Fired
Alert Rule: sre-demo-vm-cpu-alert
Description: Alert when VM CPU exceeds 85% - indicates runaway process or resource exhaustion
Resource: sre-demo-vm
Time: 02/04/2026 16:16:18 UTC
```

### Alert Configuration Details

The VM CPU alert was configured as a metric alert:

```bicep
resource vmCpuAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'sre-demo-vm-cpu-alert'
  properties: {
    severity: 2
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'HighCPU'
          metricName: 'Percentage CPU'
          operator: 'GreaterThan'
          threshold: 85
          timeAggregation: 'Average'
        }
      ]
    }
    targetResourceType: 'Microsoft.Compute/virtualMachines'
  }
}
```

### What SRE Agent Did

![SRE Agent VM Investigation](images/incident2-investigation.png)
*[SCREENSHOT: SRE Agent chat showing VM investigation and Run Command execution]*

**1. Process Capture via VM Run Command**

SRE Agent requested approval to run a safe, read-only command to capture top CPU processes:

```powershell
# Read-only diagnostic command
Get-Process | Sort-Object CPU -Descending | Select-Object -First 10 Name,CPU,Id | ConvertTo-Json
```

The agent used Azure VM Run Command (`az vm run-command invoke`) to execute PowerShell remotely:

```bash
az vm run-command invoke \
  -g rg-sre-demo-india \
  -n sre-demo-vm \
  --subscription 616dc9b8-b4aa-415f-8dcb-71bc462916c5 \
  --command-id RunPowerShellScript \
  --scripts "Get-Process | Sort-Object CPU -Descending | Select-Object -First 10 Name,CPU,Id | ConvertTo-Json"
```

**2. Runaway Process Identification**

![Process Analysis](images/incident2-process-analysis.png)
*[SCREENSHOT: SRE Agent showing the top CPU processes with runaway indicators]*

Results revealed two PowerShell processes consuming excessive CPU:

```json
[
  { "Name": "powershell", "CPU": 683.45, "Id": 3164 },
  { "Name": "powershell", "CPU": 652.12, "Id": 2776 },
  { "Name": "MsMpEng",    "CPU": 54.23,  "Id": 1892 },
  { "Name": "svchost",    "CPU": 12.34,  "Id": 1024 }
]
```

| Process | PID | CPU Time (seconds) | Assessment | Reasoning |
|---------|-----|-------------------|------------|-----------|
| powershell | 3164 | 683.45s (~11 min) | 🔴 Runaway | CPU time > 60s threshold from IRP |
| powershell | 2776 | 652.12s (~10 min) | 🔴 Runaway | CPU time > 60s threshold from IRP |
| MsMpEng | 1892 | 54.23s | ✅ Normal | Windows Defender - expected |
| svchost | 1024 | 12.34s | ✅ Normal | System process - expected |

SRE Agent correctly identified these as stress/runaway processes based on the custom instructions I provided in the Incident Response Plan:

> *"If process is 'powershell' with CPU > 80 seconds → LIKELY stress script"*

**3. Targeted Remediation**

![Remediation Execution](images/incident2-remediation.png)
*[SCREENSHOT: SRE Agent executing Stop-Process command with approval]*

With my approval, SRE Agent executed targeted process termination:

```bash
az vm run-command invoke \
  -g rg-sre-demo-india \
  -n sre-demo-vm \
  --subscription 616dc9b8-b4aa-415f-8dcb-71bc462916c5 \
  --command-id RunPowerShellScript \
  --scripts "Stop-Process -Id 3164 -Force -ErrorAction SilentlyContinue; Stop-Process -Id 2776 -Force -ErrorAction SilentlyContinue; Write-Output 'Stopped'"
```

> 💡 **Why specific PIDs?** SRE Agent targeted only the identified runaway processes (PIDs 3164, 2776) rather than killing all PowerShell processes. This minimizes blast radius and avoids disrupting legitimate automation.

**4. Recovery Verification**

![Recovery Verified](images/incident2-recovery-verified.png)
*[SCREENSHOT: Post-remediation process list showing normalized CPU]*

Post-remediation check showed:

```json
// After remediation - Top processes
[
  { "Name": "MsMpEng",  "CPU": 54.23, "Id": 1892 },  // Now the top consumer
  { "Name": "svchost",  "CPU": 12.34, "Id": 1024 },
  { "Name": "WmiPrvSE", "CPU": 8.12,  "Id": 2048 }
]
```

- ✅ PowerShell processes no longer in top CPU list
- ✅ Highest CPU consumer: `MsMpEng` (Windows Defender) at ~54s - **normal baseline**
- ✅ VM CPU normalized

### Technical Deep Dive: Understanding CPU Metrics

An important learning from this incident:

| Metric | What It Measures | When to Use |
|--------|------------------|-------------|
| `Get-Process.CPU` | **Cumulative** CPU time in seconds since process start | Identifying long-running resource hogs |
| `Get-Counter '\Processor(_Total)\% Processor Time'` | **Instantaneous** CPU percentage | Validating current system state |
| `Get-CimInstance Win32_Processor` | CPU load percentage | Quick health check |

SRE Agent initially tried to verify recovery using performance counters but encountered parsing issues. The Session Insights captured this learning for future incidents.

### Timeline

| Time (UTC) | Event | Duration |
|------------|-------|----------|
| 16:16:18 | Alert fired (CPU > 85% for 5 min) | - |
| 16:16:20 | SRE Agent acknowledged | +2s |
| 16:48:00 | Process capture approved | +32m (human delay) |
| 16:48:30 | Top processes captured | +30s |
| 16:51:00 | Runaway processes identified | +2.5m |
| 16:52:00 | Remediation approved | +1m |
| 16:52:30 | Processes terminated | +30s |
| 16:55:00 | Recovery verified | +2.5m |

**Total time from alert to resolution: ~39 minutes** (32 minutes waiting for initial human approval)

---

## Why Custom Instructions Matter

![Incident Response Plan Configuration](images/irp-configuration.png)
*[SCREENSHOT: SRE Agent portal showing Incident Response Plan setup]*

Out of the box, SRE Agent knows Azure. But it doesn't know *your* environment.

For the VM CPU scenario, I created an **Incident Response Plan** with custom instructions that taught the agent:

- What "HighCpuProcess" means (it's our test stress process)
- When it's safe to kill PowerShell processes (CPU > 60 seconds)
- How to validate recovery (check CPU percentage)
- When to escalate vs. auto-remediate

### Full Custom Instructions for VM CPU Scenario

```markdown
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
For PowerShell stress jobs:
  Get-Job -Name "HighCpuProcess*" | Stop-Job

For high-CPU PowerShell processes:
  Get-Process -Name "powershell*" | Where-Object { $_.CPU -gt 60 } | Stop-Process -Force

General process termination (use process ID from investigation):
  Stop-Process -Id <ProcessId> -Force

VALIDATION:
After remediation, verify CPU has returned to normal:
  $cpu = (Get-Counter '\Processor(_Total)\% Processor Time' -SampleInterval 2 -MaxSamples 3 | 
      Select-Object -ExpandProperty CounterSamples | 
      Measure-Object -Property CookedValue -Average).Average
  Write-Host "Current CPU: $([math]::Round($cpu, 1))%"

ESCALATION:
- If CPU remains high after killing identified processes, escalate to human operator
- If process is a critical system process, do NOT kill - escalate instead
- If unable to connect to VM, check VM health and network connectivity first
```

### How Custom Instructions Change Agent Behavior

| Without Custom Instructions | With Custom Instructions |
|-----------------------------|-------------------------|
| "I see high CPU on this VM" | "PowerShell PID 3164 has 683s CPU time, exceeding 60s threshold - confirmed runaway" |
| "Should I investigate?" | "Based on IRP criteria, this matches stress script pattern - recommending termination" |
| Generic troubleshooting | Targeted, context-aware remediation |
| May escalate unnecessarily | Knows when to act vs. escalate |

This context transformed SRE Agent from a generic troubleshooter into a teammate who understands our specific runbooks.

---

## What SRE Agent Learned (Session Insights)

![Session Insights Panel](images/session-insights.png)
*[SCREENSHOT: SRE Agent Session Insights showing timeline, evaluation, and learnings]*

After each incident, SRE Agent generates **Session Insights**—a structured summary of what happened, what went well, and what to improve. These become organizational knowledge.

### Session Insights Structure

```
TIMELINE
├── Event 1: Initial acknowledgment
├── Event 2: Symptom assessment
├── Event 3: Root cause identified
├── Event 4: Remediation executed
└── Event 5: Recovery verified

EVALUATION
├── What Went Well
│   └── Specific actions that succeeded
└── What Didn't Go Well
    └── Issues encountered + better approaches

DERIVED LEARNING
├── System Design Knowledge
│   └── Azure-specific learnings
└── Investigation Pattern
    └── Reusable troubleshooting approaches
```

### From Incident 1 (SQL Connectivity):

**What Went Well:**
> - Rapid isolation of failing backend: Used Application Insights to pinpoint the SQL dependency target with 80/80 failures
> - Layered validation before change: Validated DNS and TCP connectivity to confirm network path
> - Targeted remediation with verification: Enabled SQL public access and confirmed recovery through dependency metrics

**What Didn't Go Well:**
> - Metric query failed for HealthCheckStatus: "cannot support requested time grain: 00:01:00"
> - **Better approach**: Use supported grains (00:05:00, 01:00:00) or query Requests/Http5xx instead

**System Design Knowledge:**
> Azure SQL: Disabling publicNetworkAccess blocks App Service access unless a Private Endpoint + VNet integration is in place; enabling PNA plus an appropriate firewall rule restores reachability quickly.

**Investigation Pattern:**
> Triage pattern: platform metrics (Requests/Http5xx) → App Insights dependencies to find the failing backend → connectivity probes (DNS/TCP) → configuration check (PNA/firewall) → minimal remediation → telemetry verification.

### From Incident 2 (VM CPU):

**What Went Well:**
> - Efficient diagnostics via Run Command: Used `az vm run-command invoke` with a simple Get-Process pipeline
> - Targeted remediation: Stopped specific PIDs with minimal script lines
> - Clear verification step: Rechecked top processes to confirm normalization

**What Didn't Go Well:**
> - Safety validation blocked `Remove-Job`: "Delete operations are not allowed for safety reasons"
> - **Better approach**: Use `Stop-Job` only and avoid `Remove-Job`
> - CPU percent checks failed due to quoting/escaping in Run Command
> - **Better approach**: Use `typeperf` or `Get-CimInstance Win32_Processor`

**System Design Knowledge:**
> Windows process metrics: Get-Process CPU is cumulative seconds, not percentage; use Get-Counter or typeperf for instantaneous CPU percent to verify recovery thresholds.

**Investigation Pattern:**
> Diagnose-remediate-verify loop: capture top processes via Run Command, terminate only confirmed runaway PIDs, then re-run the same read to confirm normalization.

---

## Architecture

![Architecture Diagram](images/architecture-diagram.png)
*[SCREENSHOT: Architecture diagram or create using draw.io/Excalidraw]*

```
┌────────────────────────────────────────────────────────────────────────────┐
│                              Azure Monitor                                  │
│  ┌─────────────────────────┐    ┌─────────────────────────────────────┐   │
│  │ Web App Health Alert    │    │ VM CPU Metric Alert                  │   │
│  │ • Metric: HealthCheck   │    │ • Metric: Percentage CPU             │   │
│  │ • Threshold: < 100%     │    │ • Threshold: > 85%                   │   │
│  │ • Severity: 1 (Critical)│    │ • Severity: 2 (Warning)              │   │
│  │ • Window: 5 minutes     │    │ • Window: 5 minutes                  │   │
│  └───────────┬─────────────┘    └──────────────────┬──────────────────┘   │
│              │                                      │                       │
└──────────────┼──────────────────────────────────────┼───────────────────────┘
               │                                      │
               │        Native Integration            │
               └──────────────────┬───────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                          Azure SRE Agent                                     │
│                                                                              │
│  ┌─────────────┐   ┌─────────────┐   ┌─────────────┐   ┌─────────────┐     │
│  │  Receive    │──▶│   Gather    │──▶│  Identify   │──▶│   Propose   │     │
│  │   Alert     │   │   Context   │   │ Root Cause  │   │Remediation  │     │
│  └─────────────┘   └─────────────┘   └─────────────┘   └──────┬──────┘     │
│                                                               │             │
│  Tools Available:                                             ▼             │
│  • Azure CLI (az)            ┌─────────────┐   ┌─────────────────────────┐ │
│  • Azure Monitor Metrics     │   Human     │──▶│   Execute & Verify      │ │
│  • Application Insights      │  Approval   │   │   Remediation           │ │
│  • Log Analytics (KQL)       └─────────────┘   └─────────────────────────┘ │
│  • VM Run Command                                                           │
│  • ARM Resource Queries                                                     │
│                                                                              │
└───────────────────────────────┬─────────────────────────────────────────────┘
                                │
               ┌────────────────┴────────────────┐
               ▼                                  ▼
┌──────────────────────────┐      ┌──────────────────────────┐
│     Azure SQL Server     │      │      Windows VM          │
│                          │      │                          │
│  Actions:                │      │  Actions:                │
│  • Query config (ARM)    │      │  • Run Command (invoke)  │
│  • Update PNA setting    │      │  • Get-Process           │
│  • Create firewall rule  │      │  • Stop-Process          │
│  • Verify connectivity   │      │  • Performance counters  │
│                          │      │                          │
└──────────────────────────┘      └──────────────────────────┘
```

### Component Details

| Component | Purpose | Integration |
|-----------|---------|-------------|
| **Azure Monitor** | Detect anomalies via metric/log alerts | Native alert routing to SRE Agent |
| **Application Insights** | Dependency tracking, failure analysis | KQL queries for root cause |
| **Log Analytics** | Centralized logging, performance data | KQL queries for investigation |
| **VM Run Command** | Remote script execution on VMs | `az vm run-command invoke` |
| **ARM API** | Resource configuration queries | Read/write resource properties |

---

## Setting Up Your Own Demo

![Demo Architecture](images/demo-setup-architecture.png)
*[SCREENSHOT: Resource group showing deployed resources]*

### Prerequisites

- Azure subscription with SRE Agent Preview access
- Permissions: RBAC Admin or User Access Admin (for role assignments)
- Region: East US 2 (required for preview)
- Tools: Azure CLI, PowerShell 7+, Node.js 18+ (optional for web app)

### Infrastructure Overview

| Resource | Purpose | SKU/Tier |
|----------|---------|----------|
| Azure SQL Server | Backend database | Serverless |
| Azure SQL Database | Product data | Basic |
| App Service Plan | Web app hosting | B1 (Basic) |
| Web App | Frontend + API | Node.js 18 |
| Windows VM | CPU spike demo | Standard_B2s |
| Application Insights | Telemetry & dependencies | - |
| Log Analytics Workspace | Centralized logging | - |

### Step 1: Deploy Infrastructure

```powershell
# Clone the demo repo
git clone https://github.com/[your-repo]/SREAgent.git
cd SREAgent

# Deploy SQL scenario (Web App + SQL Database)
.\scripts\deploy.ps1 -ResourceGroupName "rg-sre-demo" -Location "eastus2"

# Wait for deployment (~5-10 minutes)
# This creates: SQL Server, Database, App Service, Application Insights, Alerts

# Deploy VM scenario
cd scenario-vm-cpu
.\deploy-vm.ps1 -AdminPassword (ConvertTo-SecureString "YourP@ss123!" -AsPlainText -Force)

# Wait for VM + Azure Monitor Agent (~10 minutes)
```

### Step 2: Create SRE Agent

![SRE Agent Creation](images/sre-agent-creation.png)
*[SCREENSHOT: Azure portal SRE Agent creation wizard]*

1. Go to [Azure SRE Agent Portal](https://aka.ms/sreagent/portal)
2. Click **Create** → Select subscription → Name: `sre-agent-demo`
3. Region: **East US 2** (required for preview)
4. Add resource group: `rg-sre-demo`
5. Click **Create**

> ⚠️ **Important**: SRE Agent needs appropriate RBAC permissions on the resource group. The agent will request `Contributor` access during setup.

### Step 3: Configure Incident Response Plans

![IRP Configuration](images/irp-setup.png)
*[SCREENSHOT: Incident Response Plan configuration in SRE Agent portal]*

Create two Incident Response Plans:

**Plan 1: Web App Health (SQL Connectivity)**
| Setting | Value |
|---------|-------|
| Incident Type | Default |
| Impacted Service | App Services |
| Priority | Sev 1 |
| Title Contains | `health` |
| Autonomy | Review (approval required) |

**Plan 2: VM High CPU**
| Setting | Value |
|---------|-------|
| Incident Type | Default |
| Impacted Service | Virtual Machines |
| Priority | Sev 2 |
| Title Contains | `CPU` |
| Autonomy | Review (approval required) |

Add custom instructions from [scenario-vm-cpu/README.md](scenario-vm-cpu/README.md).

### Step 4: Trigger Incidents

```powershell
# Scenario 1: Cause SQL connectivity failure
# This disables public network access on SQL Server
.\scripts\trigger-incident.ps1 -Action "pause"

# Wait 5-10 minutes for alert to fire

# Scenario 2: Cause CPU spike on VM
.\scenario-vm-cpu\trigger-cpu-spike.ps1 -Action start

# This runs background PowerShell jobs that consume ~90% CPU
# Wait 5-10 minutes for alert to fire (CPU > 85% for 5 min window)
```

### Step 5: Watch SRE Agent Work

![SRE Agent in Action](images/sre-agent-in-action.png)
*[SCREENSHOT: SRE Agent portal showing active investigation]*

Open the SRE Agent portal and watch it:
1. ✅ Acknowledge the alert (instant)
2. 🔍 Investigate autonomously (metrics, logs, config)
3. 🎯 Identify root cause
4. 💡 Propose remediation options
5. ✋ Wait for your approval
6. 🔧 Execute remediation
7. ✅ Verify recovery
8. 📝 Generate Session Insights

### Step 6: Cleanup

```powershell
# Remove all demo resources
.\scripts\cleanup.ps1 -ResourceGroupName "rg-sre-demo"

# Or manually via Azure CLI
az group delete --name rg-sre-demo --yes --no-wait
```

---

## Key Takeaways

### Quantitative Results

| Metric | Incident 1 (SQL) | Incident 2 (VM) |
|--------|------------------|-----------------|
| Time to Acknowledge | 1 second | 2 seconds |
| Time to Root Cause | ~10 minutes | ~3 minutes |
| Human Time Required | ~6 minutes (approval) | ~33 minutes (approvals) |
| Total Resolution Time | ~20 minutes | ~39 minutes |
| Automated Steps | 12 | 8 |

### Before vs. After Comparison

| Before SRE Agent | After SRE Agent |
|------------------|-----------------|
| Alert fires → Wait for human to wake up | Alert fires → Investigation starts immediately |
| Engineer manually queries metrics, logs | Agent queries metrics, logs, ARM configs in seconds |
| Root cause found after 20-30 mins of digging | Root cause identified in <10 mins automatically |
| Remediation requires tribal knowledge | Custom instructions encode runbooks in IRP |
| Post-incident docs written (maybe, days later) | Session Insights auto-generated immediately |
| Knowledge stays in engineer's head | Learnings captured and reusable |

### Key Benefits

1. **Faster MTTR** - Investigation starts instantly, not when humans are available
2. **Consistent Triage** - Same investigation pattern every time
3. **Knowledge Capture** - Session Insights preserve learnings
4. **Reduced Toil** - Automated data gathering and correlation
5. **Guardrails** - Approval workflow for remediation actions

---

## Lessons Learned & Best Practices

### Do's ✅

| Practice | Why |
|----------|-----|
| **Write specific IRP instructions** | Generic instructions = generic responses |
| **Include identification criteria** | Help agent distinguish safe vs. risky remediations |
| **Define escalation triggers** | Know when NOT to auto-remediate |
| **Test in Review mode first** | Validate agent behavior before enabling Autonomous |
| **Use supported metric time grains** | Avoid query failures (5m, 1h, not 1m for some metrics) |

### Don'ts ❌

| Anti-Pattern | Issue |
|--------------|-------|
| **Overly broad permissions** | Security risk; use least-privilege RBAC |
| **Complex PowerShell in Run Command** | Parsing/escaping issues; keep scripts simple |
| **Skipping recovery verification** | Agent should always validate the fix worked |
| **Using `Remove-Job` in remediations** | May trigger safety blocks; use `Stop-Job` |
| **Enabling Autonomous mode without testing** | Unintended remediations on production resources |

---

## What's Next?

### Immediate Next Steps

- **Autonomous Mode**: For trusted, well-tested scenarios, skip approval and let SRE Agent remediate automatically
- **More Scenarios**: Add database pause/resume, storage throttling, AKS pod failures
- **Teams Integration**: Get incident updates and approve remediations directly in Teams

### Future Enhancements

- **Scheduled Checks**: Combine reactive response with proactive optimization (see [Proactive Cloud Ops blog](https://techcommunity.microsoft.com/blog/appsonazureblog/proactive-cloud-ops-with-sre-agent-scheduled-checks-for-cloud-optimization/4487261))
- **GitHub Issues**: Auto-create issues for infrastructure problems linked to repos
- **Knowledge Base**: Upload runbooks, architecture docs to improve agent context
- **MCP Servers**: Connect external tools (Datadog, PagerDuty, Splunk) for broader observability

---

## Conclusion

Azure SRE Agent transforms incident response from a reactive, human-dependent process into an AI-assisted workflow that starts investigating the moment an alert fires.

In these two real-world scenarios:
- **SQL Connectivity Outage**: Agent identified misconfigured public network access and restored connectivity in ~20 minutes
- **VM CPU Spike**: Agent captured process data, identified runaway PowerShell, and terminated the culprits in ~39 minutes

The key differentiator? **Custom Instructions**. By encoding our team's runbooks and identification criteria into Incident Response Plans, SRE Agent became a context-aware teammate—not just a generic troubleshooter.

**Is it perfect?** No. We encountered metric query failures, CLI escaping issues, and safety blocks. But the Session Insights captured these learnings, making the agent better for next time.

**Is it valuable?** Absolutely. Even with human approval delays, we resolved both incidents faster than traditional triage—and with comprehensive documentation auto-generated.

---

## Learn More

- [Azure SRE Agent Documentation](https://aka.ms/sreagent/docs)
- [Azure SRE Agent Blogs](http://aka.ms/sreagent/blogs)
- [Azure SRE Agent Community](https://aka.ms/sreagent/discussions)
- [Azure SRE Agent Home Page](http://www.azure.com/sreagent)
- [Azure SRE Agent Pricing](http://aka.ms/sreagent/pricing)

**Azure SRE Agent is currently in preview.** [Get Started →](https://aka.ms/sreagent/portal)

---

## About the Author

![Author Photo](images/author-photo.png)

**[Your Name]**  
[Your Title] at [Your Company]

[LinkedIn] | [Twitter] | [GitHub]

*[Add a brief bio about yourself and your experience with SRE/Azure]*

---

## Appendix: Screenshot Checklist

Use this checklist to capture all required screenshots:

| Screenshot | File Name | Description |
|------------|-----------|-------------|
| ⬜ | `hero-sre-agent-dashboard.png` | SRE Agent portal overview with incident list |
| ⬜ | `incident1-alert-fired.png` | Azure Monitor alert showing Sev1 health check failure |
| ⬜ | `incident1-investigation-flow.png` | SRE Agent chat showing investigation steps |
| ⬜ | `incident1-app-insights-dependencies.png` | Application Insights showing SQL dependency failures |
| ⬜ | `incident1-sql-config.png` | Azure CLI output showing publicNetworkAccess: Disabled |
| ⬜ | `incident1-rca-output.png` | SRE Agent displaying root cause analysis |
| ⬜ | `incident1-remediation-approval.png` | SRE Agent asking for approval |
| ⬜ | `incident1-recovery-verified.png` | SRE Agent showing successful recovery |
| ⬜ | `incident2-alert-fired.png` | Azure Monitor showing VM CPU metric alert |
| ⬜ | `incident2-investigation.png` | SRE Agent chat showing VM investigation |
| ⬜ | `incident2-process-analysis.png` | SRE Agent showing top CPU processes |
| ⬜ | `incident2-remediation.png` | SRE Agent executing Stop-Process |
| ⬜ | `incident2-recovery-verified.png` | Post-remediation process list |
| ⬜ | `irp-configuration.png` | Incident Response Plan setup in portal |
| ⬜ | `session-insights.png` | Session Insights panel |
| ⬜ | `architecture-diagram.png` | Architecture diagram (optional - use ASCII) |
| ⬜ | `demo-setup-architecture.png` | Resource group with deployed resources |
| ⬜ | `sre-agent-creation.png` | SRE Agent creation wizard |
| ⬜ | `irp-setup.png` | IRP configuration in portal |
| ⬜ | `sre-agent-in-action.png` | SRE Agent showing active investigation |
| ⬜ | `author-photo.png` | Your professional photo |

---

*Tags: Azure SRE Agent, Incident Response, Azure Monitor, Site Reliability Engineering, AI Ops, Cloud Native, Best Practices, DevOps, Automation*

*Published: [Date]*  
*Last Updated: [Date]*
