# ADR 003: Implementación del Circuit Breaker Pattern

## Estado
**Aceptado** - 2023-12-07

## Contexto
El sistema necesita ser resiliente ante fallos de componentes downstream, especialmente la base de datos PostgreSQL. Sin protección, un fallo de la base de datos puede causar:

- **Cascading failures**: Request timeouts que consumen recursos
- **Resource exhaustion**: Connection pool agotado
- **Poor user experience**: Timeouts largos sin feedback útil
- **System instability**: Acumulación de requests pendientes

Necesitamos un mecanismo que:
- Detecte fallos automáticamente
- Falle rápido para preservar recursos
- Permita recovery automático
- Proporcione observabilidad del estado del sistema

## Decisión
**Implementar el Circuit Breaker Pattern** para proteger operaciones de base de datos críticas.

## Justificación

### El Circuit Breaker Pattern

El patrón funciona como un circuit breaker eléctrico, con tres estados:

```
    Normal Operation          Failures Detected         Testing Recovery
    ┌─────────────┐          ┌─────────────┐           ┌─────────────┐
    │   CLOSED    │──────────►│    OPEN     │──────────►│ HALF_OPEN   │
    │             │ Threshold │             │  Timeout  │             │
    │ Requests    │ Exceeded  │ Fail Fast   │  Elapsed  │ Limited     │
    │ Pass Through│           │ All Requests│           │ Testing     │
    └─────────────┘          └─────────────┘           └─────────────┘
           ▲                                                    │
           │                                                    │
           └────────────────────────────────────────────────────┘
                              Success Threshold Met
```

### Implementación Personalizada vs Librerías

**Decisión**: Implementar circuit breaker personalizado.

**Razones**:
1. **Control Total**: Adaptado a nuestras necesidades específicas
2. **Zero Dependencies**: No external dependencies adicionales
3. **Simplicity**: Solo ~50 líneas de código, fácil de entender
4. **Customization**: Fácil agregar features específicas (metrics, etc.)

```typescript
export class CircuitBreaker {
  private failures = 0;
  private successes = 0;
  private lastFailureTime?: number;
  private state: 'CLOSED' | 'OPEN' | 'HALF_OPEN' = 'CLOSED';

  constructor(
    private threshold: number = 5,        // Failures before opening
    private timeout: number = 60000,      // 1 minute recovery window
    private successThreshold: number = 2  // Successes to close circuit
  ) {}

  async execute<T>(operation: () => Promise<T>): Promise<T> {
    if (this.state === 'OPEN') {
      if (Date.now() - (this.lastFailureTime || 0) > this.timeout) {
        this.state = 'HALF_OPEN';
        this.successes = 0;
      } else {
        throw new Error('Circuit breaker is OPEN');
      }
    }

    try {
      const result = await operation();
      this.onSuccess();
      return result;
    } catch (error) {
      this.onFailure();
      throw error;
    }
  }
}
```

### Configuración Optimizada

#### Threshold Selection (5 failures)
```typescript
private threshold: number = 5
```
**Justificación**:
- **No demasiado sensible**: Evita false positives por errores transitorios
- **No demasiado permisivo**: Detecta problemas reales rápidamente
- **Basado en data**: 5 requests representan ~5 segundos de traffic normal

#### Timeout Window (60 segundos)
```typescript
private timeout: number = 60000
```
**Justificación**:
- **Balance recovery time**: Suficiente para que DB se recupere
- **User experience**: No demasiado largo para usuarios
- **Operational**: Align con monitoring intervals típicos

#### Success Threshold (2 successes)
```typescript
private successThreshold: number = 2
```
**Justificación**:
- **Confidence building**: Más que 1 success evita false recoveries
- **Fast recovery**: No demasiado conservativo
- **Resource efficient**: Minimal testing overhead

## Implementación en el Sistema

### Database Operations Protection
```typescript
// En server.ts - todos los DB queries están protegidos
app.get('/api/users', async (req: Request, res: Response) => {
  try {
    const result = await dbCircuitBreaker.execute(async () => {
      return chaosEngineer.simulateDatabaseFailure(async () => {
        return pool.query('SELECT * FROM users ORDER BY created_at DESC');
      });
    });

    res.json({ users: result.rows, count: result.rows.length });
  } catch (error) {
    logger.error('Failed to fetch users', { error, requestId: req.id });
    res.status(500).json({ 
      error: 'Failed to fetch users',
      requestId: req.id
    });
  }
});
```

### Observability Integration
```typescript
// Circuit breaker status endpoint para monitoring
app.get('/api/circuit-breaker', (req: Request, res: Response) => {
  res.json({
    database: dbCircuitBreaker.getState()
  });
});

// Example response:
{
  "database": {
    "state": "CLOSED",
    "failures": 0,
    "lastFailureTime": null
  }
}
```

### Metrics Integration
```typescript
// Métricas Prometheus para alerting
export const circuitBreakerState = new Gauge({
  name: 'circuit_breaker_state',
  help: 'Circuit breaker state (0=CLOSED, 1=OPEN, 2=HALF_OPEN)',
  labelNames: ['service']
});

// Actualización automática
circuitBreakerState.set({ service: 'database' }, stateToNumber(dbCircuitBreaker.getState().state));
```

## Beneficios Demostrados

### 1. **Fail Fast Behavior**
```typescript
// Sin Circuit Breaker: 5 second timeout por request
const result = await pool.query('SELECT * FROM users'); // Waits 5s if DB down

// Con Circuit Breaker: Immediate failure
const result = await dbCircuitBreaker.execute(async () => {
  return pool.query('SELECT * FROM users');
}); // Throws immediately if circuit OPEN
```

### 2. **Resource Protection**
- **Connection Pool**: No se agota con requests que fallarán
- **Memory**: No acumula promises pendientes
- **CPU**: No gasta ciclos en operations destinadas a fallar

### 3. **User Experience**
```typescript
// Response rápida con mensaje útil
{
  "error": "Service temporarily unavailable", 
  "requestId": "uuid",
  "retryAfter": 60
}
```

### 4. **Automatic Recovery**
- **No manual intervention**: Sistema se recupera automáticamente
- **Gradual testing**: HALF_OPEN state prueba connectivity sin overwhelm
- **Confidence building**: Múltiples successes antes de full recovery

## Testing y Validation

### Chaos Engineering Integration
```typescript
// Test circuit breaker bajo condiciones adversas
curl -X POST http://localhost:3000/api/chaos \
  -H "Content-Type: application/json" \
  -d '{"enabled": true, "errorRate": 0.8}'

// Observar state transitions:
// CLOSED → OPEN (after 5 failures)
// OPEN → HALF_OPEN (after 60 seconds)  
// HALF_OPEN → CLOSED (after 2 successes)
```

### Monitoring Dashboard
```prometheus
# Alertas recomendadas
- alert: CircuitBreakerOpen
  expr: circuit_breaker_state{service="database"} == 1
  for: 0m
  annotations:
    summary: "Database circuit breaker is OPEN"
    description: "Database connectivity issues detected"

- alert: CircuitBreakerHalfOpen
  expr: circuit_breaker_state{service="database"} == 2
  for: 2m
  annotations:
    summary: "Database circuit breaker testing recovery"
```

## Implicaciones

### Positivas:
1. **System Resilience**: Previene cascading failures
2. **Resource Efficiency**: Protege connection pools y memory
3. **Observability**: Clear insight into system health
4. **User Experience**: Fast failure con messaging útil

### Consideraciones:
1. **False Positives**: Circuit puede abrir por errores transitorios
2. **Coordination**: Multiple instances pueden tener different states
3. **Data Consistency**: Algunas operations pueden necesitar different handling

### Mitigaciones:
1. **Tuning**: Thresholds configurables por environment
2. **Monitoring**: Dashboards para observar behavior
3. **Alerting**: Notifications cuando circuit abre
4. **Documentation**: Runbooks para respuesta operational

## Future Enhancements

### Distributed Circuit Breaker
```typescript
// Para múltiples instancias, considerar Redis-based state
interface DistributedCircuitBreaker {
  getGlobalState(): Promise<CircuitState>;
  updateGlobalState(state: CircuitState): Promise<void>;
}
```

### Advanced Metrics
```typescript
// Métricas adicionales para deep observability
export const circuitBreakerTrips = new Counter({
  name: 'circuit_breaker_trips_total',
  help: 'Total number of circuit breaker trips',
  labelNames: ['service', 'reason']
});
```

## Referencias
- [Circuit Breaker Pattern - Martin Fowler](https://martinfowler.com/bliki/CircuitBreaker.html)
- [Release It! - Michael Nygard](https://www.oreilly.com/library/view/release-it-2nd/9781680504552/)
- [Netflix Hystrix Documentation](https://github.com/Netflix/Hystrix/wiki)

## Revisión
Esta implementación será revisada basada en:
- Production metrics y behavior
- False positive rates
- Recovery time effectiveness
- Team operational feedback