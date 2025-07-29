import { register, collectDefaultMetrics, Counter, Histogram, Gauge } from 'prom-client';
import { Request, Response, NextFunction } from 'express';

// Collect default metrics
collectDefaultMetrics({ register });

// Custom metrics
export const httpRequestsTotal = new Counter({
  name: 'http_requests_total',
  help: 'Total number of HTTP requests',
  labelNames: ['method', 'route', 'status']
});

export const httpRequestDuration = new Histogram({
  name: 'http_request_duration_seconds',
  help: 'Duration of HTTP requests in seconds',
  labelNames: ['method', 'route', 'status'],
  buckets: [0.001, 0.005, 0.01, 0.05, 0.1, 0.5, 1, 2, 5]
});

export const activeConnections = new Gauge({
  name: 'active_connections',
  help: 'Number of active connections'
});

export const errorRate = new Gauge({
  name: 'error_rate',
  help: 'Current error rate',
  labelNames: ['endpoint']
});

export const dbConnectionPool = new Gauge({
  name: 'db_connection_pool_size',
  help: 'Database connection pool metrics',
  labelNames: ['state'] // active, idle, waiting
});

// SLI metrics
export const sliAvailability = new Gauge({
  name: 'sli_availability',
  help: 'Service Level Indicator for availability'
});

export const sliLatency = new Gauge({
  name: 'sli_latency_p99',
  help: 'Service Level Indicator for latency (p99)'
});

export const errorBudgetRemaining = new Gauge({
  name: 'error_budget_remaining_percentage',
  help: 'Remaining error budget as percentage'
});

// Register all metrics
register.registerMetric(httpRequestsTotal);
register.registerMetric(httpRequestDuration);
register.registerMetric(activeConnections);
register.registerMetric(errorRate);
register.registerMetric(dbConnectionPool);
register.registerMetric(sliAvailability);
register.registerMetric(sliLatency);
register.registerMetric(errorBudgetRemaining);

// Middleware to track metrics
export function metricsMiddleware(req: Request, res: Response, next: NextFunction) {
  const start = Date.now();
  const route = req.route?.path || req.path;
  
  activeConnections.inc();

  res.on('finish', () => {
    const duration = (Date.now() - start) / 1000;
    const labels = { 
      method: req.method, 
      route, 
      status: res.statusCode.toString() 
    };
    
    httpRequestsTotal.inc(labels);
    httpRequestDuration.observe(labels, duration);
    activeConnections.dec();

    // Update error rate
    if (res.statusCode >= 500) {
      errorRate.inc({ endpoint: route });
    }
  });

  next();
}

// Calculate SLIs
export async function updateSLIs() {
  // Mock calculations for demo
  sliAvailability.set(0.9995); // 99.95% availability
  sliLatency.set(0.150); // 150ms p99 latency
  errorBudgetRemaining.set(75); // 75% of error budget remaining
}

export { register };