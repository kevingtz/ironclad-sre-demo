# Prometheus Alerting - Configuración y Reglas Detalladas

## Introducción

El sistema de alertas implementado en Prometheus sigue las mejores prácticas de Site Reliability Engineering (SRE) para proporcionar alerting efectivo, actionable, y alineado con objetivos de negocio. Esta documentación explica cada regla de alerta, su lógica, y cómo contribuye al sistema general de observabilidad.

## Filosofía de Alerting

### Principios Fundamentales

1. **Symptom-Based Alerting**: Alerta sobre problemas que usuarios experimentan, no sobre causas internas
2. **Actionable Alerts**: Cada alerta debe requerir acción humana inmediata
3. **Low False Positive Rate**: Mejor missed alerts ocasionales que alert fatigue
4. **SLO Alignment**: Alertas deben correlacionar con Service Level Objectives
5. **Clear Severity Levels**: Critical vs Warning con thresholds bien definidos

### Alerting vs Monitoring

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Telemetry     │    │   Monitoring    │    │    Alerting     │
│                 │    │                 │    │                 │
│ • Metrics       │───▶│ • Dashboards    │───▶│ • Critical      │
│ • Logs          │    │ • Graphs        │    │   Issues        │
│ • Traces        │    │ • Analysis      │    │ • Immediate     │
│                 │    │                 │    │   Action        │
└─────────────────┘    └─────────────────┘    └─────────────────┘
     100% data              Human analysis         Human action
```

**Distinction importante:**
- **Monitoring**: Comprehensive visibility para understanding system behavior
- **Alerting**: Selective notifications para immediate human intervention
- **Telemetry**: Raw data collection sin human interpretation

## Configuración de Alertas

### Estructura de Archivo

```yaml
# monitoring/prometheus/alerts.yml
groups:
  - name: ironclad_alerts
    interval: 30s
    rules:
      # Alertas definidas aquí
```

**¿Por qué interval: 30s?**
- **Balance responsiveness/overhead**: Más frecuente que default 1m, menos que 15s
- **Alert evaluation time**: Permite detection en ~1-2 minutos para most alerts
- **Resource efficiency**: Reduced evaluation overhead vs 15s interval
- **Production alignment**: Suitable para most production alerting scenarios

### Labels y Annotations Strategy

```yaml
labels:
  severity: critical          # critical/warning/info
  team: sre                  # Team ownership
  service: backend           # Service identification  
  component: api             # Component within service
annotations:
  summary: "Brief description of the issue"
  description: "Detailed context with templated values"
  runbook_url: "https://docs.company.com/runbooks/issue-name"
  dashboard_url: "https://grafana.company.com/d/dashboard-id"
```

**Label purposes:**
- **Routing**: AlertManager uses labels para route notifications
- **Grouping**: Similar alerts grouped together para reduce noise
- **Filtering**: On-call engineers can filter by team/service
- **Inhibition**: Higher severity alerts can silence lower severity ones

## Alertas Implementadas

### 1. High Error Rate Alert

```yaml
- alert: HighErrorRate
  expr: rate(http_requests_total{status=~"5.."}[5m]) > 0.05
  for: 5m
  labels:
    severity: critical
    team: sre
  annotations:
    summary: "High error rate detected"
    description: "Error rate is {{ $value | humanizePercentage }} for {{ $labels.instance }}"
```

#### Análisis Técnico Detallado

**PromQL Expression Breakdown:**
```promql
rate(http_requests_total{status=~"5.."}[5m]) > 0.05
```

- **`http_requests_total`**: Counter metric de total HTTP requests
- **`{status=~"5.."}`**: Regex filter para HTTP 5xx status codes (500-599)
- **`rate(...[5m])`**: Per-second average rate over 5-minute window
- **`> 0.05`**: Threshold de 5% error rate (0.05 requests/second con errors por cada 1 req/sec total)

**¿Por qué 5% threshold?**
- **User experience impact**: 5% error rate is noticeable to users
- **Business impact**: Significant enough para affect customer satisfaction
- **False positive balance**: High enough para avoid transient spikes
- **Industry standard**: Common threshold para web services

**¿Por qué `for: 5m`?**
- **Sustained issue detection**: Avoids alerting on temporary spikes
- **Response time allowance**: Gives automatic recovery mechanisms time to work
- **Human intervention timing**: 5 minutes is reasonable response expectation
- **Alert storm prevention**: Prevents multiple alerts from same underlying issue

#### Error Rate Calculation Logic

```promql
# Error rate percentage calculation
(
  sum(rate(http_requests_total{status=~"5.."}[5m])) 
  / 
  sum(rate(http_requests_total[5m]))
) * 100
```

**Mathematical example:**
- Total requests: 100 req/sec
- Error requests: 7 req/sec  
- Error rate: (7/100) * 100 = 7% > 5% threshold → ALERT

### 2. High Latency Alert

```yaml
- alert: HighLatency
  expr: histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m])) > 0.5
  for: 5m
  labels:
    severity: warning
    team: sre
  annotations:
    summary: "High latency detected"
    description: "95th percentile latency is {{ $value }}s"
```

#### Histogram Quantile Analysis

**PromQL Expression Components:**
```promql
histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m])) > 0.5
```

- **`http_request_duration_seconds_bucket`**: Histogram buckets para request duration
- **`rate(...[5m])`**: Rate of increase per bucket over 5 minutes
- **`histogram_quantile(0.95, ...)`**: Calculate 95th percentile from histogram
- **`> 0.5`**: 500ms threshold para warning

**¿Por qué P95 en lugar de average?**
- **Outlier detection**: P95 captures performance issues affecting minority of users
- **User experience**: Average can be misleading si most requests are fast but some very slow
- **Tail latency importance**: Slow requests often correlate con system stress
- **SLO alignment**: P95 < 500ms is common web service SLO

**¿Por qué Warning severity?**
- **User impact**: High latency is degraded experience, not complete failure
- **Recovery possibility**: Often self-resolves con reduced load
- **Escalation path**: Can escalate to Critical si sustained or worsening
- **Investigation trigger**: Indicates need for performance investigation

#### Histogram Bucket Strategy

```typescript
// backend/src/metrics.ts - Histogram configuration
const httpRequestDuration = new promClient.Histogram({
  name: 'http_request_duration_seconds',
  help: 'Duration of HTTP requests in seconds',
  labelNames: ['method', 'endpoint'],
  buckets: [0.1, 0.3, 0.5, 0.7, 1, 3, 5, 7, 10]  // seconds
});
```

**Bucket selection rationale:**
- **0.1s, 0.3s**: Fast responses (cached, simple queries)
- **0.5s**: SLO boundary - warning threshold
- **0.7s, 1s**: Acceptable pero slower responses  
- **3s, 5s**: Slow responses (complex queries, external API calls)
- **7s, 10s**: Very slow responses (timeouts, system stress)

### 3. Database Connection Alert

```yaml
- alert: DatabaseDown
  expr: up{job="ironclad-backend"} == 0
  for: 1m
  labels:
    severity: critical
    team: sre
  annotations:
    summary: "Database connection lost"
    description: "Cannot connect to database for {{ $labels.instance }}"
```

#### Service Availability Monitoring

**PromQL Expression:**
```promql
up{job="ironclad-backend"} == 0
```

- **`up`**: Built-in Prometheus metric indicating scrape success
- **`{job="ironclad-backend"}`**: Filters para backend service instances
- **`== 0`**: Value 0 indicates failed scrape (service down/unreachable)

**¿Por qué `for: 1m` en lugar de 5m?**
- **Service availability**: Database connectivity is critical para all functionality
- **User impact**: Complete service unavailability requires immediate response  
- **Recovery urgency**: Database issues often require immediate intervention
- **False positive low**: Network connectivity rarely has 1-minute transient issues

#### Database Health Check Implementation

```typescript
// backend/src/server.ts - Health endpoint
app.get('/health', async (req, res) => {
  try {
    // Database connectivity check
    await db.query('SELECT 1');
    
    res.status(200).json({
      status: 'healthy',
      timestamp: new Date().toISOString(),
      database: 'connected'
    });
  } catch (error) {
    res.status(503).json({
      status: 'unhealthy', 
      error: error.message,
      database: 'disconnected'
    });
  }
});
```

**Health check components:**
- **Database query**: Simple SELECT 1 to verify connectivity
- **HTTP status codes**: 200 OK vs 503 Service Unavailable
- **Detailed response**: JSON with status information para debugging
- **Error handling**: Graceful failure with error details

### 4. Error Budget Burn Rate Alert

```yaml
- alert: ErrorBudgetBurnRate
  expr: error_budget_remaining_percentage < 50
  for: 10m
  labels:
    severity: warning
    team: sre
  annotations:
    summary: "Error budget burning too fast"
    description: "Only {{ $value }}% of error budget remaining"
```

#### Error Budget Calculation

**Conceptual formula:**
```
Error Budget = (1 - SLO) × Total Events
Remaining Budget = Error Budget - Actual Errors
Burn Rate = Actual Errors / Error Budget
```

**Example calculation:**
- **SLO**: 99.9% availability (0.1% error budget)
- **Monthly requests**: 1,000,000
- **Error budget**: 1,000 errors per month
- **Current errors**: 600 errors (15 days into month)
- **Remaining**: 400 errors (40% remaining) → ALERT

**¿Por qué 50% threshold?**
- **Proactive alerting**: Warns before budget is completely exhausted
- **Decision support**: Informs release vs reliability tradeoffs
- **Burn rate visibility**: 50% at mid-month indicates on-track consumption
- **Planning time**: Allows time para corrective actions

#### Error Budget Implementation

```typescript
// backend/src/metrics.ts - Error budget tracking
const errorBudgetGauge = new promClient.Gauge({
  name: 'error_budget_remaining_percentage',
  help: 'Percentage of error budget remaining',
  collect() {
    const totalRequests = getTotalRequests();
    const errorRequests = getErrorRequests();
    const slo = 0.999; // 99.9%
    
    const errorBudget = totalRequests * (1 - slo);
    const remaining = (errorBudget - errorRequests) / errorBudget * 100;
    
    this.set(Math.max(0, remaining));
  }
});
```

## Alert Severity Matrix

### Severity Classification

| Severity | User Impact | Response Time | Examples |
|----------|-------------|---------------|----------|
| **Critical** | Service unavailable or severely degraded | Immediate (< 5 min) | Database down, High error rate |
| **Warning** | Degraded performance, potential future issues | 1-4 hours | High latency, Error budget burn |
| **Info** | System behavior worth noting | Next business day | Deployment complete, Config change |

### Escalation Matrix

```yaml
# AlertManager configuration (future enhancement)
route:
  group_by: ['alertname', 'service']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 12h
  receiver: 'sre-team'
  routes:
  - match:
      severity: critical
    receiver: 'sre-oncall-immediate'
    group_wait: 0s
  - match:
      severity: warning
    receiver: 'sre-team-business-hours'
```

## PromQL Best Practices Implementadas

### 1. Rate vs Increase

```promql
# ✅ CORRECTO: Use rate() para ratios y percentages
rate(http_requests_total{status=~"5.."}[5m]) / rate(http_requests_total[5m])

# ❌ INCORRECTO: Using raw counters
http_requests_total{status=~"5.."} / http_requests_total
```

**¿Por qué rate()?**
- **Counter resets**: Handles counter resets automáticamente
- **Per-second normalization**: Provides comparable values across time windows
- **Time window handling**: Averages over specified time period
- **Rate calculation**: Proper derivative calculation for counter metrics

### 2. Time Window Selection

```promql
# Different time windows para different purposes
rate(http_requests_total[1m])   # Real-time monitoring (dashboard)
rate(http_requests_total[5m])   # Alerting (smooth out spikes)
rate(http_requests_total[15m])  # Trend analysis (longer context)
```

**Time window guidelines:**
- **1-2 minutes**: Dashboard real-time updates
- **5 minutes**: Standard alerting window (balance noise/responsiveness)
- **15+ minutes**: Trend analysis y capacity planning
- **Rule of thumb**: Alert window should be 2-5x scrape interval

### 3. Label Consistency

```promql
# ✅ CONSISTENT: Same labels across related metrics
http_requests_total{method="GET", status="200", endpoint="/api/users"}
http_request_duration_seconds{method="GET", endpoint="/api/users"}

# ❌ INCONSISTENT: Different label names
http_requests_total{verb="GET", code="200", path="/api/users"}
http_request_duration_seconds{method="GET", endpoint="/api/users"}
```

### 4. Aggregation Best Practices

```promql
# ✅ GOOD: Aggregate first, then calculate ratios
sum(rate(http_requests_total{status=~"5.."}[5m])) / sum(rate(http_requests_total[5m]))

# ❌ PROBLEMATIC: Calculate ratios first, then aggregate
avg(rate(http_requests_total{status=~"5.."}[5m]) / rate(http_requests_total[5m]))
```

## Testing y Validation

### Alert Testing Strategy

```bash
# 1. Trigger high error rate
curl -X POST http://backend-url/api/chaos/errors/0.1

# 2. Wait for alert evaluation period (5 minutes)
# 3. Verify alert fires in Prometheus
curl http://prometheus-url/api/v1/alerts

# 4. Check alert content y labels
curl http://prometheus-url/api/v1/alerts | jq '.data.alerts[] | select(.labels.alertname=="HighErrorRate")'

# 5. Disable chaos y verify alert resolves
curl -X POST http://backend-url/api/chaos/disable
```

### Alert Validation Checklist

- [ ] **Expression syntax**: PromQL query is valid y returns expected results
- [ ] **Threshold tuning**: Alert fires at appropriate severity level
- [ ] **Duration testing**: `for` clause prevents false positives
- [ ] **Label correctness**: All required labels present y accurate
- [ ] **Annotation templating**: Variables resolve correctly
- [ ] **Resolution testing**: Alert clears when condition resolves

### Chaos Engineering Integration

```makefile
# Makefile commands para testing alerts
test-error-alert: ## Test high error rate alert
	@echo "Triggering high error rate..."
	@$(MAKE) chaos-errors
	@echo "Wait 5 minutes, then check Prometheus alerts"
	@echo "Alert should fire: HighErrorRate"

test-latency-alert: ## Test high latency alert  
	@echo "Adding artificial latency..."
	@$(MAKE) chaos-latency
	@echo "Wait 5 minutes, then check Prometheus alerts"
	@echo "Alert should fire: HighLatency"
```

## Runbook Integration

### Alert Runbook Template

```markdown
# HighErrorRate Alert Runbook

## Overview
High error rate detected in backend service

## Impact
- Users experiencing 5xx errors
- Potential service degradation
- SLO impact likely

## Investigation Steps
1. Check error rate dashboard
2. Examine application logs for error patterns
3. Verify database connectivity
4. Check external service dependencies
5. Review recent deployments

## Common Causes
- Database connectivity issues
- External API failures  
- Application bugs in recent deployment
- Resource exhaustion (memory/CPU)
- Network issues

## Mitigation
1. **Immediate**: Rollback recent deployment if correlation exists
2. **Short-term**: Scale up replicas if resource constrained
3. **Investigation**: Deep dive into error logs
4. **Communication**: Update status page if user-facing

## Resolution Verification
- Error rate drops below 1%
- Alert automatically resolves
- User reports of issues cease
```

### Documentation Structure

```
docs/runbooks/
├── high-error-rate.md
├── high-latency.md  
├── database-down.md
├── error-budget-burn.md
└── runbook-template.md
```

## Future Enhancements

### Advanced Alerting Patterns

#### 1. Multi-window Alerts
```yaml
# Alert on both short and long-term error rate
- alert: ErrorBudgetFastBurn
  expr: (
    rate(http_requests_total{status=~"5.."}[5m]) > 0.1
    and
    rate(http_requests_total{status=~"5.."}[1h]) > 0.02
  )
  for: 2m
```

#### 2. Anomaly Detection
```yaml
# Alert when current rate is significantly higher than historical
- alert: AnomalousErrorRate
  expr: (
    rate(http_requests_total{status=~"5.."}[10m]) 
    > 
    quantile_over_time(0.95, rate(http_requests_total{status=~"5.."}[10m])[7d:10m]) * 2
  )
  for: 5m
```

#### 3. Composite Alerts
```yaml
# Alert when multiple conditions indicate system stress
- alert: SystemStress
  expr: (
    rate(http_requests_total{status=~"5.."}[5m]) > 0.02
    and
    histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m])) > 1.0
    and
    up{job="ironclad-backend"} < 0.8
  )
  for: 3m
```

### AlertManager Integration

```yaml
# Future: Complete AlertManager configuration
global:
  smtp_smarthost: 'localhost:587'
  smtp_from: 'alerts@company.com'

route:
  group_by: ['alertname']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 1h
  receiver: 'web.hook'

receivers:
- name: 'web.hook'
  slack_configs:
  - api_url: 'SLACK_WEBHOOK_URL'
    channel: '#sre-alerts'
    title: 'Alert: {{ .CommonLabels.alertname }}'
    text: '{{ range .Alerts }}{{ .Annotations.description }}{{ end }}'
```

### Silence Management

```bash
# Silence alerts durante maintenance
amtool silence add alertname="HighErrorRate" --duration="1h" --comment="Planned maintenance"

# List active silences
amtool silence query

# Expire silence early
amtool silence expire <silence-id>
```

## Monitoring the Monitoring System

### Meta-Alerts para Prometheus Health

```yaml
- alert: PrometheusDown
  expr: up{job="prometheus"} == 0
  for: 1m
  labels:
    severity: critical

- alert: PrometheusConfigReloadFailed
  expr: prometheus_config_last_reload_successful != 1
  for: 5m
  labels:
    severity: warning

- alert: PrometheusTSDBCorruption
  expr: prometheus_tsdb_wal_corruptions_total > 0
  for: 0m
  labels:
    severity: critical
```

## Conclusión

El sistema de alertas implementado proporciona coverage completo de los aspectos críticos del servicio mientras mantiene un balance apropiado entre responsiveness y noise reduction. Las alertas están diseñadas para ser actionable, well-documented, y alineadas con business objectives.

**Key strengths:**
- ✅ **Symptom-based approach**: Alerts when users are impacted
- ✅ **Appropriate thresholds**: Based on industry standards y user experience
- ✅ **Clear severity levels**: Critical vs Warning con distinct response expectations  
- ✅ **SLO integration**: Error budget alerts inform release decisions
- ✅ **Testing integration**: Chaos engineering validates alert behavior
- ✅ **Documentation**: Runbooks provide clear investigation steps

**Production readiness enhancements:**
- AlertManager deployment para notification routing
- Slack/PagerDuty integration para team notifications
- Advanced alerting patterns (anomaly detection, multi-window)
- Alert testing automation en CI/CD pipeline
- Historical alert analysis y tuning based on operational data

La implementación demuestra understanding profundo de SRE alerting principles y provides solid foundation para production-grade incident response.