const express = require('express');
const path = require('path');
const sql = require('mssql');

// ============================================================================
// Application Insights Setup - MUST be before other requires
// ============================================================================
const appInsights = require('applicationinsights');

if (process.env.APPLICATIONINSIGHTS_CONNECTION_STRING || process.env.APPINSIGHTS_INSTRUMENTATIONKEY) {
  appInsights.setup()
    .setAutoDependencyCorrelation(true)
    .setAutoCollectRequests(true)
    .setAutoCollectPerformance(true, true)
    .setAutoCollectExceptions(true)
    .setAutoCollectDependencies(true)
    .setAutoCollectConsole(true, true)
    .setUseDiskRetryCaching(true)
    .start();
  
  console.log('Application Insights initialized');
}

const appInsightsClient = appInsights.defaultClient;

const app = express();
const PORT = process.env.PORT || 8080;

// Middleware
app.use(express.json());

// SQL Configuration with Azure AD Managed Identity Authentication
const sqlConfig = {
  database: process.env.SQL_DATABASE || 'productdb',
  server: process.env.SQL_SERVER || 'localhost',
  pool: {
    max: 10,
    min: 0,
    idleTimeoutMillis: 30000
  },
  options: {
    encrypt: true,
    trustServerCertificate: false
  },
  authentication: {
    type: 'azure-active-directory-default'
  }
};

// Database connection pool
let pool = null;

async function getPool() {
  if (!pool) {
    console.log('Connecting to SQL Server:', process.env.SQL_SERVER);
    pool = await sql.connect(sqlConfig);
    console.log('Connected to database successfully');
  }
  return pool;
}

// ============================================================================
// API Routes
// ============================================================================

// Health check endpoint (used by Azure Web App health monitoring)
app.get('/api/health', async (req, res) => {
  const startTime = Date.now();
  
  try {
    const poolConnection = await getPool();
    await poolConnection.request().query('SELECT 1 as health');
    
    // Track successful health check
    if (appInsightsClient) {
      appInsightsClient.trackDependency({
        name: 'SQL Health Check',
        dependencyTypeName: 'SQL',
        target: process.env.SQL_SERVER,
        data: 'SELECT 1 as health',
        duration: Date.now() - startTime,
        success: true,
        resultCode: 200
      });
    }
    
    res.json({
      status: 'healthy',
      database: 'connected',
      timestamp: new Date().toISOString(),
      server: process.env.SQL_SERVER
    });
  } catch (error) {
    pool = null; // Reset pool on connection error
    console.error('Health check failed:', error.message);
    
    // ⚠️ CRITICAL: Track as EXCEPTION in Application Insights
    if (appInsightsClient) {
      // Track as exception (shows in Failures blade)
      appInsightsClient.trackException({
        exception: error,
        properties: {
          endpoint: '/api/health',
          errorType: 'DatabaseConnectionFailure',
          sqlServer: process.env.SQL_SERVER,
          database: process.env.SQL_DATABASE
        },
        severity: appInsights.Contracts.SeverityLevel.Critical
      });
      
      // Track as failed dependency
      appInsightsClient.trackDependency({
        name: 'SQL Health Check',
        dependencyTypeName: 'SQL',
        target: process.env.SQL_SERVER,
        data: 'SELECT 1 as health',
        duration: Date.now() - startTime,
        success: false,
        resultCode: 503
      });
      
      // Track custom event for easier querying
      appInsightsClient.trackEvent({
        name: 'DatabaseConnectionFailed',
        properties: {
          errorMessage: error.message,
          sqlServer: process.env.SQL_SERVER,
          endpoint: '/api/health'
        }
      });
      
      // Force flush to send immediately
      appInsightsClient.flush();
    }
    
    res.status(503).json({
      status: 'unhealthy',
      database: 'disconnected',
      timestamp: new Date().toISOString(),
      error: error.message
    });
  }
});

// Get all products
app.get('/api/products', async (req, res) => {
  const startTime = Date.now();
  
  try {
    const poolConnection = await getPool();
    const result = await poolConnection.request().query(`
      SELECT id, name, description, price, category, stock 
      FROM Products 
      ORDER BY category, name
    `);
    
    // Track successful query
    if (appInsightsClient) {
      appInsightsClient.trackDependency({
        name: 'SQL GetProducts',
        dependencyTypeName: 'SQL',
        target: process.env.SQL_SERVER,
        data: 'SELECT * FROM Products',
        duration: Date.now() - startTime,
        success: true,
        resultCode: 200
      });
    }
    
    res.json(result.recordset);
  } catch (error) {
    pool = null;
    console.error('Database error:', error.message);
    
    // ⚠️ CRITICAL: Track as EXCEPTION in Application Insights
    if (appInsightsClient) {
      appInsightsClient.trackException({
        exception: error,
        properties: {
          endpoint: '/api/products',
          errorType: 'DatabaseConnectionFailure',
          sqlServer: process.env.SQL_SERVER,
          database: process.env.SQL_DATABASE
        },
        severity: appInsights.Contracts.SeverityLevel.Error
      });
      
      appInsightsClient.trackDependency({
        name: 'SQL GetProducts',
        dependencyTypeName: 'SQL',
        target: process.env.SQL_SERVER,
        data: 'SELECT * FROM Products',
        duration: Date.now() - startTime,
        success: false,
        resultCode: 503
      });
      
      appInsightsClient.trackEvent({
        name: 'DatabaseConnectionFailed',
        properties: {
          errorMessage: error.message,
          sqlServer: process.env.SQL_SERVER,
          endpoint: '/api/products'
        }
      });
      
      appInsightsClient.flush();
    }
    
    res.status(503).json({
      error: 'Database connection failed',
      details: error.message,
      timestamp: new Date().toISOString()
    });
  }
});

// Get product by ID
app.get('/api/products/:id', async (req, res) => {
  try {
    const poolConnection = await getPool();
    const result = await poolConnection.request()
      .input('id', sql.Int, req.params.id)
      .query('SELECT id, name, description, price, category, stock FROM Products WHERE id = @id');
    
    if (result.recordset.length === 0) {
      return res.status(404).json({ error: 'Product not found' });
    }
    
    res.json(result.recordset[0]);
  } catch (error) {
    pool = null;
    res.status(503).json({
      error: 'Database connection failed',
      details: error.message
    });
  }
});

// ============================================================================
// Serve Static Angular Frontend
// ============================================================================
app.use(express.static(path.join(__dirname, 'public')));

// SPA fallback - serve index.html for all non-API routes
app.get('*', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

// Error handling middleware
app.use((err, req, res, next) => {
  console.error('Unhandled error:', err);
  res.status(500).json({
    error: 'Internal server error',
    timestamp: new Date().toISOString()
  });
});

// Start server
app.listen(PORT, () => {
  console.log(`
╔═══════════════════════════════════════════════════════════════════╗
║           Azure SRE Agent Demo - Web Application                  ║
╠═══════════════════════════════════════════════════════════════════╣
║  Server running on port: ${PORT}                                      ║
║  Health check: /api/health                                        ║
║  Products API: /api/products                                      ║
╠═══════════════════════════════════════════════════════════════════╣
║  SQL Server: ${(process.env.SQL_SERVER || 'not configured').substring(0, 45).padEnd(45)}       ║
║  Database:   ${(process.env.SQL_DATABASE || 'not configured').padEnd(45)}       ║
╚═══════════════════════════════════════════════════════════════════╝
  `);
});
