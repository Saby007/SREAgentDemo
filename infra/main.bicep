// ============================================================================
// Azure SRE Agent Demo - Complete Infrastructure
// Deploys: Web App + Azure SQL (Serverless) + Monitoring + Alerts
// ============================================================================

targetScope = 'resourceGroup'

// Parameters
@description('Location for all resources')
param location string = resourceGroup().location

@description('Base name for all resources')
param baseName string = 'sre-demo'

@description('Azure AD Admin Object ID (your user or group object ID)')
param aadAdminObjectId string

@description('Azure AD Admin Login Name (your email or group name)')
param aadAdminLogin string

@description('Your IP address for SQL Server firewall rule')
param allowedIpAddress string = ''

// Variables
var uniqueSuffix = uniqueString(resourceGroup().id)
var sqlServerName = '${baseName}-sql-${uniqueSuffix}'
var sqlDatabaseName = 'productdb'
var logAnalyticsName = '${baseName}-logs-${uniqueSuffix}'
var appInsightsName = '${baseName}-insights-${uniqueSuffix}'
var actionGroupName = '${baseName}-action-group'
var appServicePlanName = '${baseName}-plan-${uniqueSuffix}'
var webAppName = '${baseName}-app-${uniqueSuffix}'

// ============================================================================
// Log Analytics Workspace (for monitoring)
// ============================================================================
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: logAnalyticsName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

// ============================================================================
// Application Insights (for telemetry)
// ============================================================================
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
  }
}

// ============================================================================
// Azure SQL Server (Azure AD Only Authentication)
// ============================================================================
resource sqlServer 'Microsoft.Sql/servers@2023-08-01' = {
  name: sqlServerName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    version: '12.0'
    publicNetworkAccess: 'Enabled'
    minimalTlsVersion: '1.2'
    administrators: {
      administratorType: 'ActiveDirectory'
      principalType: 'User'
      login: aadAdminLogin
      sid: aadAdminObjectId
      tenantId: subscription().tenantId
      azureADOnlyAuthentication: true
    }
  }
}

// Allow Azure services to access SQL Server
resource sqlFirewallAzure 'Microsoft.Sql/servers/firewallRules@2023-08-01' = {
  parent: sqlServer
  name: 'AllowAllWindowsAzureIps'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

// Allow your local IP to access SQL Server
resource sqlFirewallLocal 'Microsoft.Sql/servers/firewallRules@2023-08-01' = if (!empty(allowedIpAddress)) {
  parent: sqlServer
  name: 'AllowLocalIP'
  properties: {
    startIpAddress: allowedIpAddress
    endIpAddress: allowedIpAddress
  }
}

// ============================================================================
// Azure SQL Database (Serverless - supports pause/resume)
// ============================================================================
resource sqlDatabase 'Microsoft.Sql/servers/databases@2023-08-01' = {
  parent: sqlServer
  name: sqlDatabaseName
  location: location
  sku: {
    name: 'GP_S_Gen5'
    tier: 'GeneralPurpose'
    family: 'Gen5'
    capacity: 1
  }
  properties: {
    collation: 'SQL_Latin1_General_CP1_CI_AS'
    maxSizeBytes: 1073741824
    autoPauseDelay: 60
    minCapacity: json('0.5')
    zoneRedundant: false
    requestedBackupStorageRedundancy: 'Local'
  }
}

// ============================================================================
// App Service Plan (Linux for Node.js)
// ============================================================================
resource appServicePlan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: appServicePlanName
  location: location
  sku: {
    name: 'F1'
    tier: 'Free'
  }
  properties: {
    reserved: false
  }
}

// ============================================================================
// Web App (Node.js backend + Angular frontend)
// ============================================================================
resource webApp 'Microsoft.Web/sites@2023-01-01' = {
  name: webAppName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      nodeVersion: '~18'
      healthCheckPath: '/api/health'
      appSettings: [
        {
          name: 'SQL_SERVER'
          value: sqlServer.properties.fullyQualifiedDomainName
        }
        {
          name: 'SQL_DATABASE'
          value: sqlDatabaseName
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: appInsights.properties.InstrumentationKey
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsights.properties.ConnectionString
        }
        {
          name: 'SCM_DO_BUILD_DURING_DEPLOYMENT'
          value: 'true'
        }
        {
          name: 'WEBSITE_NODE_DEFAULT_VERSION'
          value: '~18'
        }
      ]
    }
  }
}

// ============================================================================
// Web App Diagnostic Settings
// ============================================================================
resource webAppDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'webapp-diagnostics'
  scope: webApp
  properties: {
    workspaceId: logAnalytics.id
    logs: [
      {
        category: 'AppServiceHTTPLogs'
        enabled: true
      }
      {
        category: 'AppServiceConsoleLogs'
        enabled: true
      }
      {
        category: 'AppServiceAppLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

// ============================================================================
// SQL Database Diagnostic Settings
// ============================================================================
resource sqlDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'sql-diagnostics'
  scope: sqlDatabase
  properties: {
    workspaceId: logAnalytics.id
    logs: [
      {
        category: 'SQLInsights'
        enabled: true
      }
      {
        category: 'Errors'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'Basic'
        enabled: true
      }
    ]
  }
}

// ============================================================================
// Action Group (for alerts)
// ============================================================================
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: actionGroupName
  location: 'global'
  properties: {
    groupShortName: 'SREDemo'
    enabled: true
  }
}

// ============================================================================
// Alert: Web App Health Check Failures
// This triggers when the /api/health endpoint fails (DB unreachable)
// ============================================================================
resource webAppHealthAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: '${baseName}-webapp-health-alert'
  location: 'global'
  properties: {
    description: 'Alert when Web App health check fails - indicates backend/database connectivity issues'
    severity: 1
    enabled: true
    scopes: [
      webApp.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'HealthCheckStatus'
          metricName: 'HealthCheckStatus'
          metricNamespace: 'Microsoft.Web/sites'
          operator: 'LessThan'
          threshold: 100
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: [
      {
        actionGroupId: actionGroup.id
      }
    ]
  }
}

// ============================================================================
// Alert: Web App HTTP 5xx Errors
// ============================================================================
resource webAppErrorAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: '${baseName}-webapp-error-alert'
  location: 'global'
  properties: {
    description: 'Alert when Web App returns HTTP 5xx server errors'
    severity: 1
    enabled: true
    scopes: [
      webApp.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'Http5xxErrors'
          metricName: 'Http5xx'
          metricNamespace: 'Microsoft.Web/sites'
          operator: 'GreaterThan'
          threshold: 5
          timeAggregation: 'Total'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: [
      {
        actionGroupId: actionGroup.id
      }
    ]
  }
}

// ============================================================================
// Alert: Database Connection Failures
// ============================================================================
resource dbConnectionAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: '${baseName}-db-connection-alert'
  location: 'global'
  properties: {
    description: 'Alert when Azure SQL Database connection failures occur (database may be paused)'
    severity: 1
    enabled: true
    scopes: [
      sqlDatabase.id
    ]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'ConnectionFailures'
          metricName: 'connection_failed'
          metricNamespace: 'Microsoft.Sql/servers/databases'
          operator: 'GreaterThan'
          threshold: 3
          timeAggregation: 'Total'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: [
      {
        actionGroupId: actionGroup.id
      }
    ]
  }
}

// ============================================================================
// Outputs
// ============================================================================
output sqlServerName string = sqlServer.name
output sqlServerFqdn string = sqlServer.properties.fullyQualifiedDomainName
output sqlDatabaseName string = sqlDatabase.name
output webAppName string = webApp.name
output webAppUrl string = 'https://${webApp.properties.defaultHostName}'
output webAppPrincipalId string = webApp.identity.principalId
output resourceGroupName string = resourceGroup().name
output logAnalyticsId string = logAnalytics.id
output appInsightsKey string = appInsights.properties.InstrumentationKey
