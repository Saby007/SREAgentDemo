require('dotenv').config();
const express = require('express');
const cors = require('cors');
const sql = require('mssql');

const app = express();
const PORT = process.env.PORT || 3000;

// Middleware
app.use(cors());
app.use(express.json());

// SQL Configuration with Azure AD Default Authentication
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
    pool = await sql.connect(sqlConfig);
  }
  return pool;
}

// Health check endpoint
app.get('/api/health', async (req, res) => {
  try {
    const poolConnection = await getPool();
    const result = await poolConnection.request().query('SELECT 1 as health');
    
    res.json({
      status: 'healthy',
      database: 'connected',
      timestamp: new Date().toISOString(),
      server: process.env.SQL_SERVER
    });
  } catch (error) {
    // Reset pool on connection error
    pool = null;
    
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
  try {
    const poolConnection = await getPool();
    const result = await poolConnection.request().query(`
      SELECT id, name, description, price, category, stock 
      FROM Products 
      ORDER BY category, name
    `);
    
    res.json(result.recordset);
  } catch (error) {
    // Reset pool on connection error
    pool = null;
    
    console.error('Database error:', error.message);
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
╔═══════════════════════════════════════════════════════════╗
║           SRE Agent Demo - Backend API                    ║
╠═══════════════════════════════════════════════════════════╣
║  Server running on: http://localhost:${PORT}                 ║
║  Health check:      http://localhost:${PORT}/api/health      ║
║  Products API:      http://localhost:${PORT}/api/products    ║
╠═══════════════════════════════════════════════════════════╣
║  SQL Server: ${(process.env.SQL_SERVER || 'not configured').padEnd(40)}  ║
║  Database:   ${(process.env.SQL_DATABASE || 'not configured').padEnd(40)}  ║
╚═══════════════════════════════════════════════════════════╝
  `);
});
