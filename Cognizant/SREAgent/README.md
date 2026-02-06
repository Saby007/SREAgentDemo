# Azure SRE Agent Demo - Automated Incident Response

This demo showcases **Azure SRE Agent** (Preview) - Microsoft's AI-driven SRE service that automatically detects, diagnoses, and remediates Azure infrastructure issues.

**Included Scenarios:**
- 🗄️ **Azure SQL Database Outage** - Auto-resume paused database
- 💻 **VM High CPU** - Auto-kill runaway process

## 🎯 Demo Scenarios

This repository includes **two demo scenarios** to showcase Azure SRE Agent capabilities:

| Scenario | Description | Folder |
|----------|-------------|--------|
| **Azure SQL Outage** | Database paused → SRE Agent resumes it | `infra/`, `scripts/` |
| **VM CPU Spike** | Runaway process → SRE Agent kills it | `scenario-vm-cpu/` |

---

### Scenario 1: Azure SQL Database Outage (Main Demo)

1. **Normal Operation**: Angular frontend displays product data from Azure SQL Database
2. **Incident Trigger**: Database is paused (simulating an outage) - UI shows connection errors
3. **Alert Detection**: Azure Monitor detects the connectivity failure and creates an alert
4. **Azure SRE Agent Response**: Automatically resumes the database

### Scenario 2: VM High CPU (Additional Demo)

1. **Normal Operation**: Windows VM running normally
2. **Incident Trigger**: Runaway process causes CPU spike to ~90%
3. **Alert Detection**: Azure Monitor metric alert fires when CPU > 85% for 5 minutes
4. **Azure SRE Agent Response**: Identifies and kills the runaway process

📖 **See [scenario-vm-cpu/README.md](scenario-vm-cpu/README.md) for detailed instructions.**

---

## 📁 Project Structure

```
SREAgent/
├── frontend/                    # Angular frontend application
│   ├── src/
│   │   ├── app/
│   │   │   ├── components/
│   │   │   └── services/
│   │   └── environments/
│   └── package.json
├── backend/                     # Node.js API backend
│   ├── src/
│   │   ├── routes/
│   │   └── services/
│   └── package.json
├── infra/                       # Azure Infrastructure (Bicep)
│   ├── main.bicep
│   ├── modules/
│   └── main.bicepparam
├── scenario-vm-cpu/             # VM CPU spike scenario
│   ├── deploy-vm.ps1
│   ├── trigger-cpu-spike.ps1
│   ├── vm-infra.bicep
│   └── README.md
└── scripts/                     # Demo & deployment scripts
    ├── deploy.ps1
    ├── trigger-incident.ps1
    └── cleanup.ps1
```

## 🚀 Quick Start

### Prerequisites

- Node.js 18+
- Azure CLI
- Angular CLI (`npm install -g @angular/cli`)
- Azure subscription with access to Azure SRE Agent Preview
- Permissions: `Microsoft.Authorization/roleAssignments/write` (RBAC Admin or User Access Admin)

### 1. Deploy Azure Infrastructure

```powershell
cd scripts
.\deploy.ps1 -ResourceGroupName "rg-sre-demo" -Location "eastus2"
```

### 2. Configure Azure SRE Agent

1. Open [Azure Portal - SRE Agent](https://aka.ms/sreagent/portal)
2. Click **Create** to create a new SRE Agent
3. Select your subscription and create a new resource group for the agent
4. Name your agent (e.g., `sre-agent-demo`)
5. Region: **East US 2** (required for preview)
6. Click **Choose resource groups** and select `rg-sre-demo`
7. Click **Create**

### 3. Run the Demo

```powershell
# Terminal 1: Start backend
cd backend
npm install
npm start

# Terminal 2: Start frontend
cd frontend
npm install
npm start

# Terminal 3: Trigger the incident (pause the database)
.\scripts\trigger-incident.ps1 -Action "pause"

# Watch the Azure SRE Agent automatically detect and fix it!
```

## 🏗️ Architecture

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│  Angular App    │────▶│   Node.js API    │────▶│  Azure SQL DB   │
│  (Frontend)     │     │   (Backend)      │     │  (Serverless)   │
└─────────────────┘     └──────────────────┘     └────────┬────────┘
                                                          │
                        ┌──────────────────┐              │
                        │  Azure Monitor   │◀─────────────┘
                        │  (Alerts)        │   Connection Failure
                        └────────┬─────────┘
                                 │
                                 │ Native Integration
                                 ▼
                        ┌──────────────────┐
                        │  Azure SRE Agent │
                        │    (Preview)     │
                        └────────┬─────────┘
                                 │
                                 │ 1. Detect Incident
                                 │ 2. AI-Powered RCA
                                 │ 3. Suggest Fix
                                 │ 4. Execute Remediation
                                 ▼
                        ┌──────────────────┐
                        │ Database Resumed │
                        │   App Restored   │
                        └──────────────────┘
```

## 📊 Components

### Frontend (Angular)
- Simple product catalog UI
- Real-time connection status indicator
- Auto-refresh to show recovery

### Backend (Node.js + Express)
- REST API for product data
- Azure SQL Database connectivity using `mssql` package
- Health check endpoints

### Azure SRE Agent
- **Native Azure Service** (not custom code)
- Connects to Azure Monitor alerts automatically
- AI-powered diagnostics and RCA
- Manages all Azure services via CLI/REST APIs
- Requires approval for remediation actions

### Infrastructure (Bicep)
- Azure SQL Server (serverless tier - supports pause/resume)
- Azure SQL Database with sample data
- Azure Monitor Alert Rules (availability, connection failures)
- Action Groups configured for SRE Agent
- Application Insights for telemetry

## 🔧 Configuration

### Environment Variables

| Variable | Description |
|----------|-------------|
| `SQL_SERVER` | Azure SQL Server FQDN |
| `SQL_DATABASE` | Database name |
| `SQL_USER` | SQL admin username |
| `SQL_PASSWORD` | SQL admin password |

### Azure SRE Agent Settings

After creating the SRE Agent, you can:
- **Chat with your agent**: Ask questions like "Why is my database not responding?"
- **View incidents**: Monitor detected incidents in the portal
- **Configure incident platform**: Optionally connect to PagerDuty or ServiceNow

## 🎬 Demo Script

### Step 1: Show Normal Operation
1. Open the Angular app at `http://localhost:4200`
2. Show products loading from the database
3. Point out the "Connected" status indicator

### Step 2: Trigger the Incident
```powershell
.\scripts\trigger-incident.ps1 -Action "pause"
```
1. Refresh the Angular app - show the error state
2. Open Azure SRE Agent in the portal

### Step 3: SRE Agent in Action
1. Show the incident detected in SRE Agent
2. Click on the incident to see the RCA
3. Show the AI analysis identifying "Database is paused"
4. Approve the suggested remediation (resume database)
5. Watch the database come back online

### Step 4: Verify Recovery
1. Refresh the Angular app
2. Show products loading again
3. Show the incident resolution in SRE Agent

## 📝 License

MIT
