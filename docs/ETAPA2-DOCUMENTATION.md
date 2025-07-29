# Documentación Técnica - Etapa 2: Kubernetes y Monitoreo

## Resumen Ejecutivo

La Etapa 2 implementa la orquestación con Kubernetes y un stack completo de monitoreo para el sistema SRE de Ironclad. Esta fase transforma la aplicación de un entorno local con Docker Compose a un ambiente de producción escalable con observabilidad completa.

## Arquitectura de Kubernetes

### Diseño de Namespaces y Separación de Responsabilidades

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: ironclad-demo
```

**¿Por qué un namespace dedicado?**
- **Aislamiento de recursos**: Previene conflictos de nombres con otros servicios del cluster
- **Gestión de políticas**: Permite aplicar NetworkPolicies, ResourceQuotas y RBAC específicos
- **Facilita limpieza**: `kubectl delete namespace ironclad-demo` elimina todos los recursos
- **Organización**: Agrupa lógicamente todos los componentes del sistema

### Gestión de Secretos y Configuración

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: postgres-secret
  namespace: ironclad-demo
type: Opaque
data:
  POSTGRES_PASSWORD: aXJvbmNsYWRfcGFzcw==  # ironclad_pass en base64
```

**Decisiones de seguridad implementadas:**
- **Secretos separados de ConfigMaps**: Información sensible (contraseñas) va en Secrets
- **Base64 encoding**: Kubernetes requirement, no es encriptación real
- **Namespace scoping**: Los secretos solo son accesibles dentro del namespace
- **Principio de menor privilegio**: Cada servicio accede solo a sus secretos necesarios

**Limitaciones conocidas y mejoras futuras:**
- En producción real, usar Kubernetes Secrets encryption at rest
- Considerar herramientas como Sealed Secrets o External Secrets Operator
- Implementar rotación automática de credenciales

## Base de Datos PostgreSQL en Kubernetes

### StatefulSet vs Deployment

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
spec:
  serviceName: postgres
  replicas: 1
  volumeClaimTemplates:
  - metadata:
      name: postgres-storage
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 1Gi
```

**¿Por qué StatefulSet en lugar de Deployment?**
- **Identidad estable**: Los pods tienen nombres predecibles (postgres-0, postgres-1, etc.)
- **Orden de despliegue**: Los pods se crean/eliminan en orden específico
- **Almacenamiento persistente**: Cada pod mantiene su propio volumen persistente
- **DNS estable**: El servicio headless proporciona DNS consistente

**Configuración de persistencia:**
- **PersistentVolumeClaim**: Garantiza que los datos sobrevivan a reinicios de pods
- **ReadWriteOnce**: Solo un pod puede montar el volumen (apropiado para PostgreSQL)
- **1Gi de storage**: Suficiente para demo, escalable según necesidades

### Configuración de Base de Datos

```yaml
env:
- name: POSTGRES_DB
  value: ironclad
- name: POSTGRES_USER
  value: ironclad_user
- name: POSTGRES_PASSWORD
  valueFrom:
    secretKeyRef:
      name: postgres-secret
      key: POSTGRES_PASSWORD
```

**Estrategia de inicialización:**
- Base de datos y usuario creados automáticamente en primer arranque
- Contraseña inyectada desde Secret para seguridad
- Ready/Liveness probes aseguran disponibilidad antes de conexiones

## Backend Application Deployment

### Estrategia de Despliegue

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend
spec:
  replicas: 3
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1
      maxSurge: 1
```

**¿Por qué 3 réplicas?**
- **Alta disponibilidad**: Tolerancia a fallos de nodos individuales
- **Distribución de carga**: Tráfico distribuido entre múltiples instancias
- **Rolling updates**: Permite actualizaciones sin downtime
- **Resource efficiency**: Balance entre disponibilidad y uso de recursos

**Rolling Update Strategy:**
- `maxUnavailable: 1`: Máximo 1 pod indisponible durante actualización
- `maxSurge: 1`: Máximo 1 pod adicional durante actualización
- Garantiza al menos 2 pods activos en todo momento

### Horizontal Pod Autoscaler (HPA)

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: backend-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: backend
  minReplicas: 3
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
```

**Lógica de auto-escalado:**
- **CPU threshold**: 70% de utilización promedio
- **Min replicas**: 3 para mantener alta disponibilidad base
- **Max replicas**: 10 para evitar runaway scaling
- **Scaling behavior**: Kubernetes evalúa cada 15 segundos por defecto

### Pod Disruption Budget (PDB)

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: backend-pdb
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app: backend
```

**Propósito del PDB:**
- **Voluntary disruptions**: Protege durante maintenance del cluster
- **Node draining**: Asegura servicio continuo durante actualizaciones de nodos
- **minAvailable: 2**: Mantiene al menos 2 pods funcionando siempre
- **Coordination**: Kubernetes coordina disruptions respetando el budget

### Network Policy para Seguridad

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: backend-netpol
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector: {}
    ports:
    - protocol: TCP
      port: 3000
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: postgres
    ports:
    - protocol: TCP
      port: 5432
  - to: {}
    ports:
    - protocol: TCP
      port: 53
    - protocol: UDP
      port: 53
```

**Política de seguridad de red:**
- **Default deny**: Bloquea todo tráfico no explícitamente permitido
- **Ingress**: Permite conexiones entrantes en puerto 3000 desde cualquier namespace
- **Egress a PostgreSQL**: Solo permite conexiones salientes a pods de PostgreSQL en puerto 5432
- **DNS access**: Permite consultas DNS (puerto 53 TCP/UDP) para resolución de nombres
- **Principio de menor privilegio**: Mínimos permisos necesarios para funcionar

## Stack de Monitoreo

### Arquitectura de Observabilidad

El stack de monitoreo implementa el patrón de observabilidad de tres pilares:
1. **Métricas**: Prometheus para recolección y almacenamiento
2. **Logs**: Structured logging con Winston (implementado en Etapa 1)
3. **Traces**: Foundation preparada para futuras implementaciones de tracing

### Prometheus Configuration

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-config
data:
  prometheus.yml: |
    global:
      scrape_interval: 15s
      evaluation_interval: 15s
    scrape_configs:
      - job_name: 'kubernetes-pods'
        kubernetes_sd_configs:
          - role: pod
            namespaces:
              names:
                - ironclad-demo
```

**Service Discovery Pattern:**
- **Kubernetes SD**: Descubrimiento automático de pods con anotaciones
- **Annotation-based**: Pods con `prometheus.io/scrape: "true"` son automáticamente monitoreados
- **Dynamic**: Nuevos pods son detectados sin reconfiguración manual
- **Namespace scoping**: Solo monitorea pods en `ironclad-demo` namespace

**Relabeling Configuration:**
```yaml
relabel_configs:
  - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
    action: keep
    regex: true
  - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
    action: replace
    target_label: __metrics_path__
    regex: (.+)
```

**¿Cómo funciona el relabeling?**
- **Keep action**: Solo procesa pods con annotation `prometheus.io/scrape: "true"`
- **Path replacement**: Usa `prometheus.io/path` annotation para el endpoint de métricas
- **Port mapping**: Combina IP del pod con puerto desde `prometheus.io/port` annotation
- **Label mapping**: Añade labels de Kubernetes (namespace, pod name) a las métricas

### Prometheus RBAC

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: prometheus
rules:
- apiGroups: [""]
  resources:
  - nodes
  - nodes/proxy
  - services
  - endpoints
  - pods
  verbs: ["get", "list", "watch"]
```

**¿Por qué ClusterRole en lugar de Role?**
- **Cross-namespace visibility**: Prometheus puede necesitar monitorear múltiples namespaces
- **Node-level metrics**: Acceso a métricas de nodos del cluster
- **Service discovery**: Capacidad de descobrir servicios en todo el cluster
- **Future scalability**: Facilita expansión del monitoreo a otros namespaces

### Alerting Rules Implementation

```yaml
groups:
  - name: ironclad_alerts
    interval: 30s
    rules:
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

**Filosofía de alerting:**
- **SLI-based alerts**: Alertas basadas en Service Level Indicators reales
- **Symptom-based**: Alerta sobre síntomas del usuario, no causas internas
- **Severity levels**: Critical/Warning para diferentes niveles de escalación
- **Team ownership**: Labels que identifican al equipo responsable

**Métricas clave monitoreadas:**
1. **Error rate**: `rate(http_requests_total{status=~"5.."}[5m]) > 0.05` (5% error rate)
2. **Latency**: `histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m])) > 0.5` (P95 > 500ms)
3. **Availability**: `up{job="ironclad-backend"} == 0` (service down)
4. **Error budget**: `error_budget_remaining_percentage < 50` (budget burn rate)

## Grafana Dashboard Implementation

### Provisioning Strategy

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-datasources
data:
  prometheus.yaml: |
    apiVersion: 1
    datasources:
      - name: Prometheus
        type: prometheus
        access: proxy
        url: http://prometheus:9090
        isDefault: true
```

**¿Por qué provisioning automático?**
- **Infrastructure as Code**: Configuración versionada y reproducible
- **Zero-touch deployment**: Grafana arranca completamente configurado
- **Consistency**: Misma configuración en todos los entornos
- **Automation**: No requiere configuración manual post-deployment

### Dashboard Configuration

```json
{
  "dashboard": {
    "title": "Ironclad SRE Dashboard",
    "panels": [
      {
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0},
        "id": 1,
        "title": "Request Rate",
        "targets": [{
          "expr": "sum(rate(http_requests_total[5m])) by (method)"
        }]
      }
    ]
  }
}
```

**Panel design principles:**
- **Golden Signals**: Focus en Rate, Errors, Duration, Saturation
- **Business metrics**: KPIs que importan al negocio
- **Operational metrics**: Información necesaria para troubleshooting
- **Historical context**: Ventanas de tiempo que permiten identificar trends

## Automation y Deployment

### Makefile Strategy

```makefile
check-tools: ## Check required tools
	@echo "Checking required tools..."
	@command -v docker >/dev/null 2>&1 || { echo "docker is required but not installed."; exit 1; }
	@command -v kubectl >/dev/null 2>&1 || { echo "kubectl is required but not installed."; exit 1; }
	@command -v minikube >/dev/null 2>&1 || { echo "minikube is required but not installed."; exit 1; }
	@echo "All required tools are installed ✓"
```

**¿Por qué validation de herramientas?**
- **Fail fast**: Detecta problemas antes de comenzar deployment
- **User experience**: Mensajes claros sobre dependencias faltantes
- **CI/CD readiness**: Automated pipelines pueden validar prerequisites
- **Documentation**: Self-documenting dependencies del proyecto

### Minikube Integration

```makefile
start-minikube: ## Start minikube
	@echo "Starting minikube..."
	minikube start --cpus=4 --memory=8192 --driver=docker
	minikube addons enable metrics-server
	@echo "Minikube started ✓"
```

**Configuración de recursos:**
- **4 CPUs**: Suficiente para backend + PostgreSQL + monitoring stack
- **8GB RAM**: Permite HPA testing y monitoring overhead
- **Docker driver**: Más confiable que VirtualBox en entornos development
- **Metrics-server addon**: Necesario para HPA functionality

### Build Strategy

```makefile
build-backend: ## Build backend Docker image
	@echo "Building backend image..."
	cd backend && npm install
	eval $(minikube docker-env) && docker build -t ironclad-backend:latest ./backend
	@echo "Backend image built ✓"
```

**¿Por qué `minikube docker-env`?**
- **Local registry**: Usa el Docker daemon de minikube directamente
- **No push required**: Imágenes están disponibles inmediatamente en minikube
- **Development speed**: Evita push/pull desde registry externo
- **Network efficiency**: No transferencia de imágenes por red

### Deployment Orchestration

```makefile
deploy: deploy-backend deploy-monitoring ## Deploy everything
	@echo "Deployment complete! ✓"
	@echo ""
	@echo "Getting service URLs..."
	@$(MAKE) get-urls
```

**Orden de deployment:**
1. **Namespace**: Crea el contenedor para todos los recursos
2. **Secrets**: Configuración sensible disponible para otros componentes
3. **PostgreSQL**: Base de datos lista antes que la aplicación
4. **Backend**: Aplicación conecta a base de datos existente
5. **Monitoring**: Stack de observabilidad monitorea aplicación funcionando

### Service Discovery

```makefile
get-urls: ## Get service URLs
	@echo "Service URLs:"
	@echo "Backend: http://$(minikube service backend -n $(NAMESPACE) --url | head -1)"
	@echo "Prometheus: http://$(minikube service prometheus -n $(NAMESPACE) --url)"
	@echo "Grafana: http://$(minikube service grafana -n $(NAMESPACE) --url)"
```

**¿Por qué `minikube service`?**
- **LoadBalancer simulation**: Minikube no tiene LoadBalancer real, simula con NodePort
- **URL generation**: Genera URLs accesibles desde host machine
- **Port mapping**: Maneja el mapping entre ServicePort y NodePort automáticamente

## Testing y Chaos Engineering Integration

### Chaos Testing Commands

```makefile
chaos-enable: ## Enable chaos engineering
	@BACKEND_URL=$(minikube service backend -n $(NAMESPACE) --url | head -1) && \
	curl -X POST $$BACKEND_URL/api/chaos/enable

chaos-latency: ## Add 500ms latency
	@BACKEND_URL=$(minikube service backend -n $(NAMESPACE) --url | head -1) && \
	curl -X POST $$BACKEND_URL/api/chaos/latency/500
```

**Chaos engineering en Kubernetes:**
- **Runtime configuration**: Chaos se habilita/configura en tiempo de ejecución
- **Service discovery**: Usa minikube service URL para encontrar endpoints
- **Multiple chaos types**: Latency injection, error rate increase, circuit breaker testing
- **Observability**: Efectos del chaos son visibles en Prometheus/Grafana

## Security Considerations

### Pod Security Standards

Aunque no implementado explícitamente en esta etapa, la arquitectura está preparada para:
- **Security contexts**: Run containers as non-root user
- **Resource limits**: Prevent resource exhaustion attacks  
- **Network policies**: Micro-segmentation implemented
- **Secrets management**: Sensitive data separated from configuration

### Future Security Enhancements

1. **Pod Security Standards**: Implement restricted security contexts
2. **Service mesh**: Considerar Istio para mTLS automático
3. **Image scanning**: Integrate container vulnerability scanning
4. **RBAC refinement**: Principle of least privilege en service accounts
5. **Admission controllers**: Validate security policies en deployment time

## Performance y Escalabilidad

### Resource Management

```yaml
resources:
  requests:
    memory: "512Mi"
    cpu: "500m"
  limits:
    memory: "1Gi"
    cpu: "1000m"
```

**Request vs Limits strategy:**
- **Requests**: Guaranteed resources, used for scheduling decisions
- **Limits**: Maximum resources, prevents resource starvation
- **2:1 ratio**: Allows bursting while preventing runaway consumption
- **Memory limits**: Prevents OOMKilled scenarios en production

### Horizontal vs Vertical Scaling

**Horizontal Scaling (HPA):**
- **Stateless design**: Backend pods son completamente stateless
- **Load distribution**: Nginx ingress distribuye carga automáticamente
- **Database bottleneck**: PostgreSQL es el potential bottleneck, no web tier
- **Cost efficiency**: Scale up/down based on actual demand

**Vertical Scaling considerations:**
- **Database scaling**: PostgreSQL podría beneficiarse de vertical scaling
- **Memory-intensive workloads**: Algunos workloads requieren más memoria, no más pods
- **Node constraints**: Vertical scaling limitado por node capacity

## Monitoring y Observabilidad

### Métricas Clave (Golden Signals)

1. **Latency**: Request duration histograms
   ```promql
   histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))
   ```

2. **Traffic**: Request rate per service
   ```promql  
   sum(rate(http_requests_total[5m])) by (service)
   ```

3. **Errors**: Error rate percentage
   ```promql
   sum(rate(http_requests_total{status=~"5.."}[5m])) / sum(rate(http_requests_total[5m]))
   ```

4. **Saturation**: Resource utilization
   ```promql
   rate(container_cpu_usage_seconds_total[5m])
   ```

### SLOs y Error Budgets

```yaml
- alert: ErrorBudgetBurnRate
  expr: error_budget_remaining_percentage < 50
  for: 10m
  labels:
    severity: warning
    team: sre
```

**Error Budget Implementation:**
- **99.9% availability SLO**: Permite 43.2 minutos de downtime por mes
- **Error budget burn rate**: Monitorea qué tan rápido se consume el budget
- **Alert thresholds**: 50% remaining triggers warning, 10% triggers critical
- **Decision framework**: Error budget informa release vs reliability decisions

## Lessons Learned y Best Practices

### Lo que funcionó bien:

1. **Namespace isolation**: Simplifica management y cleanup
2. **ConfigMap + Secret separation**: Clear security boundary
3. **StatefulSet para PostgreSQL**: Proper persistent storage handling
4. **HPA + PDB combination**: Balances availability y resource efficiency
5. **Prometheus service discovery**: Zero-configuration monitoring
6. **Makefile automation**: Developer-friendly deployment experience

### Challenges encontrados:

1. **Cluster connectivity**: kubectl timeouts durante validation
2. **Image registry**: Minikube docker-env requiere understanding de networking
3. **Service discovery timing**: Wait conditions necesarios para proper startup order
4. **Resource sizing**: Balance entre demo resources y realistic production sizing

### Production Readiness Gap Analysis:

**Que falta para producción:**
1. **External LoadBalancer**: Real load balancer, no minikube simulation
2. **Persistent storage class**: Production-grade storage con backup/restore
3. **TLS certificates**: HTTPS termination y certificate management
4. **Log aggregation**: Centralized logging con ELK stack o similar
5. **Backup strategy**: Database backup automation
6. **Disaster recovery**: Multi-region deployment strategy
7. **Security scanning**: Container image y vulnerability scanning
8. **Service mesh**: Istio para advanced traffic management y security

## Conclusión

La Etapa 2 transforma exitosamente la aplicación de desarrollo local a una arquitectura de producción cloud-native. La implementación demuestra comprensión profunda de patrones de Kubernetes, observabilidad, y SRE practices.

**Key achievements:**
- ✅ **Scalable architecture**: HPA + multiple replicas
- ✅ **High availability**: PDB + proper resource distribution  
- ✅ **Security**: NetworkPolicies + Secret management
- ✅ **Observability**: Complete monitoring stack
- ✅ **Automation**: One-command deployment
- ✅ **Chaos engineering**: Runtime failure injection
- ✅ **Production patterns**: StatefulSets, proper resource management

**Next steps**: La implementación está lista para Etapa 3, que expandirá dashboards, añadirá demo scripts completos, y completará la documentación arquitectónica final.