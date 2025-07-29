# ADR 004: Chaos Engineering Implementation

## Estado
**Aceptado** - 2023-12-07

## Contexto
Para validar la resiliencia del sistema y construir confianza en nuestros patterns de reliability, necesitamos una forma controlada de introducir fallos y observar el comportamiento del sistema.

**Principios de Chaos Engineering** (Netflix):
1. **Build a hypothesis** around steady state behavior
2. **Vary real-world events** that could disrupt steady state
3. **Run experiments** in production (o production-like environments)
4. **Minimize blast radius** to limit impact
5. **Learn and improve** system resilience

El sistema actual incluye varios mecanismos de resiliencia:
- Circuit breaker para database operations
- Rate limiting para abuse protection
- Input validation para security
- Structured logging para observability

**Necesitamos validar** que estos mecanismos funcionan correctamente bajo condiciones adversas.

## Decisión
**Implementar un módulo de Chaos Engineering configurable** que permita inyectar fallos controlados para testing de resiliencia.

## Justificación

### Why Chaos Engineering?

#### 1. **Proactive Failure Discovery**
```typescript
// Sin Chaos: Descubres fallos cuando ocurren en producción
// Con Chaos: Descubres fallos en ambientes controlados

// Ejemplo: ¿Qué pasa si la DB está lenta?
await chaosEngineer.simulateLatency(5000); // 5s delay
// Resultado: Circuit breaker debe activarse después de threshold
```

#### 2. **Confidence Building**
- **Team confidence**: "Sabemos que el sistema maneja X failure mode"
- **Operational confidence**: "Los runbooks funcionan"  
- **Architecture confidence**: "Los patterns de resiliencia son efectivos"

#### 3. **Real-world Validation**
```typescript
// Test scenarios que son difíciles de simular con unit tests:
- Network partitions
- Cascading failures  
- Resource exhaustion
- Third-party service degradation
```

### Implementation Strategy

#### Built-in vs External Tools

**Decisión**: Implementar chaos capabilities integradas en la aplicación.

**Justificación**:
- **Simplicity**: No requiere herramientas externas (Chaos Monkey, Litmus, etc.)
- **Control**: Fine-grained control sobre failure injection
- **Development**: Useful durante development y CI/CD
- **Gradual rollout**: Fácil de enable/disable per environment

### Chaos Capabilities Implemented

#### 1. **HTTP Error Injection**
```typescript
export class ChaosEngineer {
  middleware() {
    return async (req: Request, res: Response, next: NextFunction) => {
      if (!this.config.enabled) {
        return next();
      }

      // Inject random errors
      if (Math.random() < this.config.errorRate) {
        logger.warn('Chaos: Injecting 500 error', { path: req.path });
        return res.status(500).json({ 
          error: 'Internal Server Error (Chaos)', 
          chaos: true 
        });
      }

      next();
    };
  }
}
```

**Testing Goals**:
- ¿Frontend maneja 500 errors gracefully?
- ¿Circuit breaker se activa correctamente?
- ¿Metrics y alertas funcionan?

#### 2. **Latency Injection**
```typescript
// Inject random latency
if (Math.random() < this.config.latencyRate) {
  const delay = Math.floor(Math.random() * this.config.latencyMs);
  logger.warn(`Chaos: Injecting ${delay}ms latency`, { path: req.path });
  await new Promise(resolve => setTimeout(resolve, delay));
}
```

**Testing Goals**:
- ¿Frontend timeouts configurados correctamente?
- ¿Users reciben feedback adecuado?
- ¿Sistema mantiene performance bajo load?

#### 3. **Database Failure Simulation**
```typescript
async simulateDatabaseFailure<T>(operation: () => Promise<T>): Promise<T> {
  if (this.config.enabled && Math.random() < this.config.errorRate) {
    throw new Error('Simulated database connection failure');
  }
  return operation();
}
```

**Testing Goals**:
- ¿Circuit breaker protege contra DB failures?
- ¿Connection pool se recupera correctamente?
- ¿Error handling es consistente?

## Configuration Management

### Environment-based Configuration
```typescript
interface ChaosConfig {
  enabled: boolean;        // Master switch
  errorRate: number;       // 0-1 probability of errors
  latencyMs: number;       // Maximum latency to inject  
  latencyRate: number;     // 0-1 probability of latency
}

// Configuration via environment variables
constructor() {
  this.config = {
    enabled: process.env.CHAOS_ENABLED === 'true',
    errorRate: parseFloat(process.env.CHAOS_ERROR_RATE || '0'),
    latencyMs: parseInt(process.env.CHAOS_LATENCY_MS || '0'),
    latencyRate: parseFloat(process.env.CHAOS_LATENCY_RATE || '0')
  };
}
```

### Runtime Configuration
```typescript
// API endpoint para control dinámico (desarrollo/testing)
app.post('/api/chaos', (req: Request, res: Response) => {
  const newConfig = req.body;
  chaosEngineer.updateConfig(newConfig);
  
  logger.info('Chaos configuration updated', newConfig);
  
  res.json({
    message: 'Chaos configuration updated',
    config: chaosEngineer.getConfig()
  });
});
```

### Safety Mechanisms

#### 1. **Environment Restrictions**
```typescript
// Solo enable en non-production por default
if (config.nodeEnv === 'production' && !process.env.CHAOS_PRODUCTION_OVERRIDE) {
  this.config.enabled = false;
  logger.warn('Chaos engineering disabled in production');
}
```

#### 2. **Rate Limiting**
```typescript
// Limitar chaos rate para minimizar blast radius
const maxErrorRate = config.nodeEnv === 'production' ? 0.1 : 1.0;
if (newConfig.errorRate > maxErrorRate) {
  throw new Error(`Error rate cannot exceed ${maxErrorRate} in ${config.nodeEnv}`);
}
```

#### 3. **Observability**
```typescript
// Log all chaos actions para analysis
logger.warn('Chaos: Injecting failure', {
  type: 'error_injection',
  path: req.path,
  config: this.config,
  timestamp: Date.now()
});
```

## Testing Scenarios

### Scenario 1: Database Failure Recovery
```bash
# Setup: Enable high error rate for DB operations
curl -X POST http://localhost:3000/api/chaos \
  -H "Content-Type: application/json" \
  -d '{"enabled": true, "errorRate": 0.8, "latencyRate": 0}'

# Test: Make multiple requests
for i in {1..20}; do
  curl -s http://localhost:3000/api/users | jq '.error'
done

# Expected Results:
# 1. First few requests succeed
# 2. After 5 failures, circuit breaker opens
# 3. Subsequent requests fail fast with circuit breaker error
# 4. After timeout, circuit enters HALF_OPEN
# 5. When chaos disabled, circuit closes

# Validation:
curl http://localhost:3000/api/circuit-breaker
# Should show state transitions
```

### Scenario 2: Frontend Resilience Testing
```bash
# Setup: Inject random latency  
curl -X POST http://localhost:3000/api/chaos \
  -H "Content-Type: application/json" \
  -d '{"enabled": true, "errorRate": 0, "latencyMs": 5000, "latencyRate": 0.5}'

# Test: Simulate user interactions
# - Form submissions
# - Page navigation  
# - API calls

# Expected Results:
# 1. 50% of requests have 0-5s additional latency
# 2. Frontend shows loading states appropriately
# 3. Users receive feedback about slow operations
# 4. No timeouts or crashes
```

### Scenario 3: Load Testing with Chaos
```bash
# Setup: Moderate chaos during load test
curl -X POST http://localhost:3000/api/chaos \
  -H "Content-Type: application/json" \
  -d '{"enabled": true, "errorRate": 0.1, "latencyMs": 1000, "latencyRate": 0.2}'

# Load test with Apache Bench
ab -n 1000 -c 10 http://localhost:3000/api/users

# Expected Results:
# 1. ~10% requests fail (chaos errors)
# 2. ~20% requests slower (latency injection)
# 3. System remains stable
# 4. Performance degrades gracefully
# 5. Recovery after chaos disabled
```

## Metrics and Observability

### Chaos Metrics
```typescript
// Métricas específicas para chaos engineering
export const chaosInjections = new Counter({
  name: 'chaos_injections_total',
  help: 'Total number of chaos injections',
  labelNames: ['type', 'endpoint']
});

// En middleware:
chaosInjections.inc({ type: 'error', endpoint: req.path });
```

### Grafana Dashboard
```json
{
  "title": "Chaos Engineering",
  "panels": [
    {
      "title": "Chaos Injection Rate",
      "targets": [
        "rate(chaos_injections_total[5m])"
      ]
    },
    {
      "title": "Circuit Breaker State During Chaos",
      "targets": [
        "circuit_breaker_state"
      ]
    },
    {
      "title": "Error Rate Impact",
      "targets": [
        "rate(http_requests_total{status=~'5..'}[5m])"
      ]
    }
  ]
}
```

## Benefits Demonstrated

### 1. **System Understanding**
```typescript
// Chaos experiments revelan:
// - Cuánto failure rate puede manejar el sistema
// - Tiempo de recovery después de fallos
// - Effectiveness de circuit breakers
// - User experience bajo condiciones adversas
```

### 2. **Operational Confidence**  
```bash
# Team knowledge validado:
# - ¿Alertas se disparan correctamente?
# - ¿Runbooks son efectivos?
# - ¿Escalation procedures funcionan?
# - ¿Recovery procedures son adecuados?
```

### 3. **Continuous Improvement**
```typescript
// Chaos engineering como parte de:
// - CI/CD pipeline (automated chaos tests)
// - Regular operational drills
// - Performance testing
// - Security testing (chaos + penetration testing)
```

## Production Considerations

### 1. **Gradual Rollout**
```typescript
// Start with low impact in production
const productionConfig = {
  enabled: true,
  errorRate: 0.001,      // 0.1% error rate
  latencyMs: 100,        // Max 100ms additional latency
  latencyRate: 0.01      // 1% of requests
};
```

### 2. **Monitoring Durante Chaos**
```bash
# Critical metrics to watch:
# - Error budget consumption
# - User-facing error rates
# - SLA/SLO compliance
# - Customer support tickets
```

### 3. **Automated Safety**
```typescript
// Auto-disable si impact demasiado alto
if (errorRate > sloThreshold) {
  chaosEngineer.updateConfig({ enabled: false });
  logger.error('Chaos disabled due to SLO impact');
  // Send alert to on-call
}
```

## Future Enhancements

### 1. **Advanced Failure Modes**
```typescript
// Network partitions
// Memory pressure
// CPU exhaustion  
// Disk space issues
// Third-party service failures
```

### 2. **Intelligent Chaos**
```typescript
// Machine learning para:
// - Optimal chaos timing
// - Failure mode selection
// - Impact prediction
// - Automatic tuning
```

### 3. **Integration with Monitoring**
```typescript
// Chaos experiments triggered por:
// - Deployment events
// - Performance degradation
// - Scheduled maintenance windows
// - On-demand testing
```

## Referencias
- [Principles of Chaos Engineering](https://principlesofchaos.org/)
- [Netflix Chaos Engineering](https://netflix.github.io/chaosmonkey/)
- [Google's DiRT Program](https://landing.google.com/sre/sre-book/chapters/disaster-recovery-testing/)
- [Chaos Engineering: O'Reilly Book](https://www.oreilly.com/library/view/chaos-engineering/9781491988459/)

## Revisión
Esta implementación será evaluada basada en:
- Número de fallos discovery in controlled vs production
- Reduction en MTTR (Mean Time To Recovery)
- Team confidence metrics
- System stability improvements
- False positive rates en alerting