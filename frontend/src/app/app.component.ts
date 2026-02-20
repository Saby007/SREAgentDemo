import { Component, OnInit, OnDestroy } from '@angular/core';
import { CommonModule } from '@angular/common';
import { HttpClient } from '@angular/common/http';
import { interval, Subscription, catchError, of } from 'rxjs';

interface Product {
  id: number;
  name: string;
  description: string;
  price: number;
  category: string;
  stock: number;
}

interface HealthStatus {
  status: 'healthy' | 'unhealthy';
  database: string;
  timestamp: string;
  error?: string;
}

@Component({
  selector: 'app-root',
  standalone: true,
  imports: [CommonModule],
  template: `
    <div class="app-container">
      <!-- Header -->
      <header class="header">
        <div class="header-content">
          <h1>🛍️ Product Catalog</h1>
          <div class="status-badge" [class]="connectionStatus">
            <span class="status-dot"></span>
            <span class="status-text">{{ connectionStatus === 'connected' ? 'Connected' : connectionStatus === 'connecting' ? 'Connecting...' : 'Disconnected' }}</span>
          </div>
        </div>
        <p class="subtitle">Azure SRE Agent Demo - Real-time Database Connectivity</p>
      </header>

      <!-- Connection Status Banner -->
      <div class="status-banner" [class]="connectionStatus" *ngIf="connectionStatus !== 'connected'">
        <div class="banner-content">
          <span class="banner-icon">{{ connectionStatus === 'connecting' ? '🔄' : '⚠️' }}</span>
          <div class="banner-text">
            <strong>{{ connectionStatus === 'connecting' ? 'Connecting to database...' : 'Database Connection Lost' }}</strong>
            <p *ngIf="errorMessage">{{ errorMessage }}</p>
            <p *ngIf="connectionStatus === 'disconnected'">The Azure SRE Agent should detect this incident automatically.</p>
          </div>
          <span class="retry-info" *ngIf="connectionStatus === 'disconnected'">Retrying in {{ retryCountdown }}s</span>
        </div>
      </div>

      <!-- Main Content -->
      <main class="main-content">
        <!-- Loading State -->
        <div class="loading-container" *ngIf="loading && connectionStatus === 'connecting'">
          <div class="spinner"></div>
          <p>Loading products from Azure SQL Database...</p>
        </div>

        <!-- Error State -->
        <div class="error-container" *ngIf="connectionStatus === 'disconnected' && !loading">
          <div class="error-icon">🔌</div>
          <h2>Unable to Load Products</h2>
          <p>The database connection is currently unavailable.</p>
          <div class="error-details">
            <code>{{ errorMessage }}</code>
          </div>
          <button class="retry-button" (click)="loadProducts()">
            🔄 Retry Now
          </button>
        </div>

        <!-- Products Grid -->
        <div class="products-grid" *ngIf="products.length > 0 && connectionStatus === 'connected'">
          <div class="product-card" *ngFor="let product of products">
            <div class="product-category">{{ product.category }}</div>
            <h3 class="product-name">{{ product.name }}</h3>
            <p class="product-description">{{ product.description }}</p>
            <div class="product-footer">
              <span class="product-price">\${{ product.price.toFixed(2) }}</span>
              <span class="product-stock" [class.low-stock]="product.stock < 10">
                {{ product.stock }} in stock
              </span>
            </div>
          </div>
        </div>
      </main>

      <!-- Footer -->
      <footer class="footer">
        <div class="footer-content">
          <p>🤖 Monitored by <strong>Azure SRE Agent</strong></p>
          <p class="last-check">Last health check: {{ lastCheckTime }}</p>
        </div>
      </footer>
    </div>
  `,
  styles: [`
    .app-container {
      min-height: 100vh;
      display: flex;
      flex-direction: column;
    }

    .header {
      background: linear-gradient(135deg, #0078d4 0%, #005a9e 100%);
      color: white;
      padding: 24px 32px;
      box-shadow: 0 2px 8px rgba(0, 0, 0, 0.15);
    }

    .header-content {
      display: flex;
      justify-content: space-between;
      align-items: center;
      max-width: 1200px;
      margin: 0 auto;
    }

    .header h1 {
      font-size: 28px;
      font-weight: 700;
    }

    .subtitle {
      max-width: 1200px;
      margin: 8px auto 0;
      opacity: 0.9;
      font-size: 14px;
    }

    .status-badge {
      display: flex;
      align-items: center;
      gap: 8px;
      padding: 8px 16px;
      border-radius: 20px;
      font-size: 14px;
      font-weight: 500;
    }

    .status-badge.connected {
      background: rgba(16, 185, 129, 0.2);
      border: 1px solid rgba(16, 185, 129, 0.5);
    }

    .status-badge.connecting {
      background: rgba(251, 191, 36, 0.2);
      border: 1px solid rgba(251, 191, 36, 0.5);
    }

    .status-badge.disconnected {
      background: rgba(239, 68, 68, 0.2);
      border: 1px solid rgba(239, 68, 68, 0.5);
    }

    .status-dot {
      width: 10px;
      height: 10px;
      border-radius: 50%;
    }

    .connected .status-dot {
      background: #10b981;
      box-shadow: 0 0 8px #10b981;
    }

    .connecting .status-dot {
      background: #fbbf24;
      animation: pulse 1s infinite;
    }

    .disconnected .status-dot {
      background: #ef4444;
      animation: pulse 1s infinite;
    }

    @keyframes pulse {
      0%, 100% { opacity: 1; }
      50% { opacity: 0.5; }
    }

    .status-banner {
      padding: 16px 32px;
    }

    .status-banner.connecting {
      background: #fef3c7;
      border-bottom: 2px solid #f59e0b;
    }

    .status-banner.disconnected {
      background: #fee2e2;
      border-bottom: 2px solid #ef4444;
    }

    .banner-content {
      max-width: 1200px;
      margin: 0 auto;
      display: flex;
      align-items: center;
      gap: 16px;
    }

    .banner-icon {
      font-size: 24px;
    }

    .banner-text {
      flex: 1;
    }

    .banner-text p {
      margin-top: 4px;
      font-size: 14px;
      opacity: 0.8;
    }

    .retry-info {
      font-weight: 600;
      padding: 8px 16px;
      background: rgba(0, 0, 0, 0.1);
      border-radius: 8px;
    }

    .main-content {
      flex: 1;
      max-width: 1200px;
      margin: 0 auto;
      padding: 32px;
      width: 100%;
    }

    .loading-container, .error-container {
      text-align: center;
      padding: 80px 20px;
    }

    .spinner {
      width: 48px;
      height: 48px;
      border: 4px solid #e5e7eb;
      border-top-color: #0078d4;
      border-radius: 50%;
      animation: spin 1s linear infinite;
      margin: 0 auto 20px;
    }

    @keyframes spin {
      to { transform: rotate(360deg); }
    }

    .error-icon {
      font-size: 64px;
      margin-bottom: 20px;
    }

    .error-container h2 {
      font-size: 24px;
      margin-bottom: 8px;
      color: #ef4444;
    }

    .error-details {
      background: #1a1a2e;
      color: #ef4444;
      padding: 16px 24px;
      border-radius: 8px;
      margin: 20px auto;
      max-width: 600px;
      font-family: 'Consolas', monospace;
      font-size: 13px;
    }

    .retry-button {
      background: #0078d4;
      color: white;
      border: none;
      padding: 12px 24px;
      border-radius: 8px;
      font-size: 16px;
      font-weight: 500;
      cursor: pointer;
      transition: background 0.2s;
    }

    .retry-button:hover {
      background: #005a9e;
    }

    .products-grid {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
      gap: 24px;
    }

    .product-card {
      background: white;
      border-radius: 12px;
      padding: 24px;
      box-shadow: 0 2px 8px rgba(0, 0, 0, 0.08);
      transition: transform 0.2s, box-shadow 0.2s;
    }

    .product-card:hover {
      transform: translateY(-4px);
      box-shadow: 0 8px 24px rgba(0, 0, 0, 0.12);
    }

    .product-category {
      display: inline-block;
      background: #e0f2fe;
      color: #0369a1;
      padding: 4px 12px;
      border-radius: 12px;
      font-size: 12px;
      font-weight: 500;
      margin-bottom: 12px;
    }

    .product-name {
      font-size: 18px;
      font-weight: 600;
      margin-bottom: 8px;
      color: #1a1a2e;
    }

    .product-description {
      color: #6b7280;
      font-size: 14px;
      margin-bottom: 16px;
      line-height: 1.5;
    }

    .product-footer {
      display: flex;
      justify-content: space-between;
      align-items: center;
      padding-top: 16px;
      border-top: 1px solid #e5e7eb;
    }

    .product-price {
      font-size: 20px;
      font-weight: 700;
      color: #0078d4;
    }

    .product-stock {
      font-size: 13px;
      color: #10b981;
      font-weight: 500;
    }

    .product-stock.low-stock {
      color: #f59e0b;
    }

    .footer {
      background: #1a1a2e;
      color: white;
      padding: 20px 32px;
      text-align: center;
    }

    .footer-content p {
      margin: 4px 0;
    }

    .last-check {
      font-size: 12px;
      opacity: 0.7;
    }
  `]
})
export class AppComponent implements OnInit, OnDestroy {
  products: Product[] = [];
  connectionStatus: 'connected' | 'connecting' | 'disconnected' = 'connecting';
  errorMessage = '';
  loading = true;
  lastCheckTime = '';
  retryCountdown = 10;
  
  private apiUrl = 'http://localhost:3000/api';
  private healthCheckSubscription?: Subscription;
  private retrySubscription?: Subscription;

  constructor(private http: HttpClient) {}

  ngOnInit(): void {
    this.loadProducts();
    this.startHealthCheck();
  }

  ngOnDestroy(): void {
    this.healthCheckSubscription?.unsubscribe();
    this.retrySubscription?.unsubscribe();
  }

  loadProducts(): void {
    this.loading = true;
    this.connectionStatus = 'connecting';
    
    this.http.get<Product[]>(`${this.apiUrl}/products`).pipe(
      catchError(error => {
        this.connectionStatus = 'disconnected';
        this.errorMessage = error.error?.error || error.message || 'Connection failed';
        this.loading = false;
        this.startRetryCountdown();
        return of([]);
      })
    ).subscribe(products => {
      if (products.length > 0) {
        this.products = products;
        this.connectionStatus = 'connected';
        this.errorMessage = '';
        this.stopRetryCountdown();
      }
      this.loading = false;
    });
  }

  private startHealthCheck(): void {
    this.healthCheckSubscription = interval(5000).subscribe(() => {
      this.checkHealth();
    });
  }

  private checkHealth(): void {
    this.http.get<HealthStatus>(`${this.apiUrl}/health`).pipe(
      catchError(error => {
        return of({ status: 'unhealthy' as const, database: 'error', timestamp: new Date().toISOString(), error: error.message });
      })
    ).subscribe(health => {
      this.lastCheckTime = new Date(health.timestamp).toLocaleTimeString();
      
      if (health.status === 'healthy' && this.connectionStatus !== 'connected') {
        this.loadProducts();
      } else if (health.status === 'unhealthy' && this.connectionStatus === 'connected') {
        this.connectionStatus = 'disconnected';
        this.errorMessage = health.error || 'Database connection lost';
        this.startRetryCountdown();
      }
    });
  }

  private startRetryCountdown(): void {
    this.retryCountdown = 10;
    this.stopRetryCountdown();
    
    this.retrySubscription = interval(1000).subscribe(() => {
      this.retryCountdown--;
      if (this.retryCountdown <= 0) {
        this.loadProducts();
        this.retryCountdown = 10;
      }
    });
  }

  private stopRetryCountdown(): void {
    this.retrySubscription?.unsubscribe();
    this.retrySubscription = undefined;
  }
}
