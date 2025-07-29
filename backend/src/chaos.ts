import { Router, Request, Response } from 'express';
import { logger } from './logger';

const router = Router();

let chaosConfig = {
  latencyMs: 0,
  errorRate: 0,
  enabled: false
};

// Middleware to inject chaos
export function chaosMiddleware(req: Request, res: Response, next: Function) {
  if (!chaosConfig.enabled) {
    return next();
  }

  // Inject latency
  if (chaosConfig.latencyMs > 0) {
    setTimeout(() => {
      continueWithChaos();
    }, chaosConfig.latencyMs);
  } else {
    continueWithChaos();
  }

  function continueWithChaos() {
    // Inject errors based on error rate
    if (chaosConfig.errorRate > 0 && Math.random() < chaosConfig.errorRate) {
      logger.warn('Chaos: Injecting error', { 
        path: req.path, 
        errorRate: chaosConfig.errorRate 
      });
      return res.status(500).json({ 
        error: 'Chaos monkey struck!',
        chaosConfig 
      });
    }
    next();
  }
}

// Chaos control endpoints
router.post('/chaos/enable', (req: Request, res: Response) => {
  chaosConfig.enabled = true;
  logger.warn('Chaos engineering enabled', chaosConfig);
  res.json({ message: 'Chaos enabled', config: chaosConfig });
});

router.post('/chaos/disable', (req: Request, res: Response) => {
  chaosConfig.enabled = false;
  chaosConfig.latencyMs = 0;
  chaosConfig.errorRate = 0;
  logger.info('Chaos engineering disabled');
  res.json({ message: 'Chaos disabled' });
});

router.post('/chaos/latency/:ms', (req: Request, res: Response) => {
  const ms = parseInt(req.params.ms);
  if (isNaN(ms) || ms < 0 || ms > 10000) {
    return res.status(400).json({ error: 'Invalid latency value (0-10000)' });
  }
  
  chaosConfig.latencyMs = ms;
  chaosConfig.enabled = true;
  logger.warn(`Chaos: Latency injection set to ${ms}ms`);
  res.json({ message: `Latency set to ${ms}ms`, config: chaosConfig });
});

router.post('/chaos/errors/:rate', (req: Request, res: Response) => {
  const rate = parseFloat(req.params.rate);
  if (isNaN(rate) || rate < 0 || rate > 1) {
    return res.status(400).json({ error: 'Invalid error rate (0-1)' });
  }
  
  chaosConfig.errorRate = rate;
  chaosConfig.enabled = true;
  logger.warn(`Chaos: Error rate set to ${rate * 100}%`);
  res.json({ message: `Error rate set to ${rate * 100}%`, config: chaosConfig });
});

router.get('/chaos/status', (req: Request, res: Response) => {
  res.json(chaosConfig);
});

export const chaosRouter = router;