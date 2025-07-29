import express, { Request, Response, NextFunction } from 'express';
import helmet from 'helmet';
import cors from 'cors';
import rateLimit from 'express-rate-limit';
import { v4 as uuidv4 } from 'uuid';
import { config } from './config';
import { logger } from './logger';
import { pool, initDatabase, checkDatabaseHealth } from './database';
import { register, metricsMiddleware, updateSLIs, httpRequestsTotal } from './metrics';
import { validateUser } from './validation';
import { chaosRouter, chaosMiddleware } from './chaos';
import { CircuitBreaker } from './circuitBreaker';

const app = express();

// Circuit breaker for database operations
const dbCircuitBreaker = new CircuitBreaker(5, 60000, 2);

// Request ID middleware
app.use((req: Request, res: Response, next: NextFunction) => {
  req.id = uuidv4();
  res.setHeader('X-Request-ID', req.id);
  next();
});

// Security middleware
app.use(helmet());
app.use(cors());
app.use(express.json());

// Rate limiting
const limiter = rateLimit({
  windowMs: config.rateLimiting.windowMs,
  max: config.rateLimiting.max,
  standardHeaders: true,
  legacyHeaders: false,
  handler: (req, res) => {
    logger.warn('Rate limit exceeded', { 
      ip: req.ip, 
      path: req.path,
      requestId: req.id 
    });
    res.status(429).json({ 
      error: 'Too many requests', 
      retryAfter: req.rateLimit?.resetTime 
    });
  }
});

app.use('/api', limiter);

// Chaos middleware (for testing)
app.use(chaosMiddleware);

// Metrics middleware
app.use(metricsMiddleware);

// Request logging
app.use((req: Request, res: Response, next: NextFunction) => {
  const start = Date.now();
  
  res.on('finish', () => {
    const duration = Date.now() - start;
    logger.info('HTTP Request', {
      requestId: req.id,
      method: req.method,
      path: req.path,
      statusCode: res.statusCode,
      duration,
      userAgent: req.get('user-agent'),
      ip: req.ip
    });
  });
  
  next();
});

// Health check endpoint
app.get('/health', async (req: Request, res: Response) => {
  const dbHealthy = await checkDatabaseHealth();
  const health = {
    status: dbHealthy ? 'healthy' : 'unhealthy',
    timestamp: new Date().toISOString(),
    checks: {
      database: dbHealthy ? 'healthy' : 'unhealthy',
      circuitBreaker: dbCircuitBreaker.getState()
    }
  };

  res.status(dbHealthy ? 200 : 503).json(health);
});

// Readiness endpoint
app.get('/ready', async (req: Request, res: Response) => {
  try {
    await dbCircuitBreaker.execute(() => checkDatabaseHealth());
    res.status(200).json({ status: 'ready' });
  } catch (error) {
    res.status(503).json({ 
      status: 'not ready', 
      reason: 'Database connection failed' 
    });
  }
});

// Metrics endpoint
app.get('/metrics', async (req: Request, res: Response) => {
  try {
    await updateSLIs();
    res.set('Content-Type', register.contentType);
    res.end(await register.metrics());
  } catch (error) {
    res.status(500).end();
  }
});

// Create user endpoint
app.post('/api/users', validateUser, async (req: Request, res: Response) => {
  const startTime = Date.now();
  
  try {
    const result = await dbCircuitBreaker.execute(async () => {
      const { first_name, middle_name, last_name, email, phone_number, date_of_birth } = req.body;
      
      // Convert date format from MM/DD/YYYY to YYYY-MM-DD for PostgreSQL
      const [month, day, year] = date_of_birth.split('/');
      const pgDate = `${year}-${month.padStart(2, '0')}-${day.padStart(2, '0')}`;
      
      return await pool.query(
        `INSERT INTO users (first_name, middle_name, last_name, email, phone_number, date_of_birth) 
         VALUES ($1, $2, $3, $4, $5, $6) 
         RETURNING id, first_name, middle_name, last_name, email, phone_number, 
                   to_char(date_of_birth, 'MM/DD/YYYY') as date_of_birth, created_at`,
        [first_name, middle_name || null, last_name, email, phone_number, pgDate]
      );
    });

    const user = result.rows[0];
    
    logger.info('User created successfully', { 
      userId: user.id, 
      requestId: req.id,
      duration: Date.now() - startTime 
    });
    
    res.status(201).json({
      data: user,
      meta: {
        requestId: req.id,
        duration: Date.now() - startTime
      }
    });
  } catch (error: any) {
    logger.error('Failed to create user', { 
      error: error.message, 
      requestId: req.id,
      stack: error.stack 
    });
    
    if (error.code === '23505') { // Unique constraint violation
      return res.status(409).json({ 
        error: 'Email already exists',
        requestId: req.id 
      });
    }
    
    res.status(500).json({ 
      error: 'Internal server error',
      requestId: req.id 
    });
  }
});

// Get all users endpoint
app.get('/api/users', async (req: Request, res: Response) => {
  try {
    const result = await dbCircuitBreaker.execute(async () => {
      return await pool.query(
        `SELECT id, first_name, middle_name, last_name, email, phone_number, 
                to_char(date_of_birth, 'MM/DD/YYYY') as date_of_birth, created_at 
         FROM users 
         ORDER BY created_at DESC 
         LIMIT 100`
      );
    });
    
    res.json({
      data: result.rows,
      meta: {
        count: result.rows.length,
        requestId: req.id
      }
    });
  } catch (error: any) {
    logger.error('Failed to fetch users', { 
      error: error.message, 
      requestId: req.id 
    });
    
    res.status(500).json({ 
      error: 'Internal server error',
      requestId: req.id 
    });
  }
});

// Update user endpoint
app.put('/api/users/:id', validateUser, async (req: Request, res: Response) => {
  try {
    const { id } = req.params;
    const { first_name, middle_name, last_name, email, phone_number, date_of_birth } = req.body;
    
    const [month, day, year] = date_of_birth.split('/');
    const pgDate = `${year}-${month.padStart(2, '0')}-${day.padStart(2, '0')}`;
    
    const result = await dbCircuitBreaker.execute(async () => {
      return await pool.query(
        `UPDATE users 
         SET first_name = $1, middle_name = $2, last_name = $3, 
             email = $4, phone_number = $5, date_of_birth = $6,
             updated_at = CURRENT_TIMESTAMP
         WHERE id = $7
         RETURNING id, first_name, middle_name, last_name, email, phone_number, 
                   to_char(date_of_birth, 'MM/DD/YYYY') as date_of_birth, updated_at`,
        [first_name, middle_name || null, last_name, email, phone_number, pgDate, id]
      );
    });
    
    if (result.rows.length === 0) {
      return res.status(404).json({ 
        error: 'User not found',
        requestId: req.id 
      });
    }
    
    res.json({
      data: result.rows[0],
      meta: { requestId: req.id }
    });
  } catch (error: any) {
    logger.error('Failed to update user', { error: error.message, requestId: req.id });
    res.status(500).json({ error: 'Internal server error', requestId: req.id });
  }
});

// Delete user endpoint
app.delete('/api/users/:id', async (req: Request, res: Response) => {
  try {
    const { id } = req.params;
    
    const result = await dbCircuitBreaker.execute(async () => {
      return await pool.query('DELETE FROM users WHERE id = $1 RETURNING id', [id]);
    });
    
    if (result.rows.length === 0) {
      return res.status(404).json({ 
        error: 'User not found',
        requestId: req.id 
      });
    }
    
    logger.info('User deleted', { userId: id, requestId: req.id });
    res.status(204).send();
  } catch (error: any) {
    logger.error('Failed to delete user', { error: error.message, requestId: req.id });
    res.status(500).json({ error: 'Internal server error', requestId: req.id });
  }
});

// Chaos engineering routes
app.use('/api', chaosRouter);

// SLO endpoint
app.get('/api/slo', async (req: Request, res: Response) => {
  res.json({
    slos: [
      {
        name: 'availability',
        target: 0.999,
        current: 0.9995,
        description: '99.9% of requests should be successful'
      },
      {
        name: 'latency',
        target: 0.95,
        current: 0.97,
        description: '95% of requests should complete within 200ms'
      }
    ],
    errorBudget: {
      total: 43.2, // minutes per month for 99.9% SLO
      consumed: 2.16, // minutes
      remaining: 41.04, // minutes
      percentage: 95 // percentage remaining
    }
  });
});

// Error handler
app.use((err: Error, req: Request, res: Response, next: NextFunction) => {
  logger.error('Unhandled error', {
    error: err.message,
    stack: err.stack,
    requestId: req.id
  });
  
  res.status(500).json({
    error: 'Internal server error',
    requestId: req.id
  });
});

// Graceful shutdown
let server: any;

async function startServer() {
  try {
    await initDatabase();
    
    server = app.listen(config.port, () => {
      logger.info(`Server started on port ${config.port}`, {
        environment: config.nodeEnv,
        pid: process.pid
      });
    });
  } catch (error) {
    logger.error('Failed to start server', error);
    process.exit(1);
  }
}

async function gracefulShutdown(signal: string) {
  logger.info(`${signal} received, starting graceful shutdown`);
  
  if (server) {
    server.close(async () => {
      logger.info('HTTP server closed');
      
      try {
        await pool.end();
        logger.info('Database connections closed');
        process.exit(0);
      } catch (error) {
        logger.error('Error during shutdown', error);
        process.exit(1);
      }
    });
  }
}

process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));
process.on('SIGINT', () => gracefulShutdown('SIGINT'));

// Start the server
startServer();

// Extend Express Request type
declare global {
  namespace Express {
    interface Request {
      id?: string;
      rateLimit?: {
        resetTime?: Date;
      };
    }
  }
}