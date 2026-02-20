using 'main.bicep'

param location = 'eastus2'
param baseName = 'sre-demo'
param sqlAdminLogin = 'sqladmin'
param sqlAdminPassword = '<REPLACE_WITH_SECURE_PASSWORD>'
param allowedIpAddress = '' // Optional: Add your IP address for direct SQL access
