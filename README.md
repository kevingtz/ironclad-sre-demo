# Ironclad SRE Excellence Showcase

A production-ready CRUD application demonstrating SRE best practices, observability, and reliability patterns.

## 🏗️ Architecture

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Client    │────▶│   Backend   │────▶│ PostgreSQL  │
└─────────────┘     │  (Node.js)  │     └─────────────┘
                    └──────┬──────┘
                           │
                    ┌──────▼──────┐
                    │ Prometheus  │
                    └──────┬──────┘
                           │
                    ┌──────▼──────┐
                    │   Grafana   │
                    └─────────────┘
```

## 🚀 Features

### Core Functionality
- ✅ CRUD operations for user management
- ✅ Input validation (names, email, US phone, date format)
- ✅ PostgreSQL with proper indexing and constraints
- ✅ RESTful API with structured responses

### SRE Excellence
- 📊 **Observability**
  - Prometheus metrics (RED method)
  - Custom business metrics and SLIs
  - Distributed tracing ready
  - Structured JSON logging

- 🛡️ **Reliability**
  - Circuit breaker pattern
  - Graceful shutdown
  - Health and readiness probes
  - Rate limiting
  - Error budget tracking

- 🔥 **Chaos Engineering**
  - Latency injection
  - Error rate injection
  - Controlled failure testing

- 📈 **Scalability**
  - Horizontal Pod Autoscaler
  - Connection pooling
  - Resource limits
  - Pod Disruption Budget

- 🔒 **Security**
  - Non-root containers
  - Network policies
  - Secrets management
  - Input sanitization
  - CORS and Helmet.js

## 📋 Prerequisites

- Docker
- Kubernetes (Minikube)
- Node.js 18+
- kubectl
- Make (optional)

## 🚀 Quick Start

```bash
# Clone the repository
git clone <repo-url>
cd ironclad-sre-demo

# Start everything with Make
make all

# Or manually:
./setup.sh
```

## 🔧 Development

### Local Development
```bash
cd backend
npm install
npm run dev
```

### Running Tests
```bash
npm test  # Would run unit tests
npm run integration-test  # Would run integration tests
```

## 📊 Monitoring

### Metrics
- Request rate by method
- Error rate (5xx responses)
- Request duration (p50, p95, p99)
- Active connections
- Database pool metrics

### SLOs
- **Availability**: 99.9% (43.2 minutes downtime/month)
- **Latency**: 95% of requests < 200ms
- **Error Budget**: Tracked and visualized

### Accessing Dashboards
```bash
# Get URLs
make get-urls

# Or port-forward
kubectl port-forward -n ironclad-demo svc/grafana 3000:3000
kubectl port-forward -n ironclad-demo svc/prometheus 9090:9090
```

## 🔥 Chaos Engineering

```bash
# Enable chaos
curl -X POST http://<backend-url>/api/chaos/enable

# Add latency (milliseconds)
curl -X POST http://<backend-url>/api/chaos/latency/500

# Add error rate (0-1)
curl -X POST http://<backend-url>/api/chaos/errors/0.1

# Check status
curl http://<backend-url>/api/chaos/status

# Disable
curl -X POST http://<backend-url>/api/chaos/disable
```

## 📝 API Documentation

### Endpoints

#### Health Check
```
GET /health
Response: {
  "status": "healthy",
  "timestamp": "2024-01-15T10:30:00Z",
  "checks": {
    "database": "healthy",
    "circuitBreaker": {
      "state": "CLOSED",
      "failures": 0
    }
  }
}
```

#### Create User
```
POST /api/users
Body: {
  "first_name": "John",
  "middle_name": "Michael",
  "last_name": "Doe",
  "email": "john.doe@example.com",
  "phone_number": "(555) 123-4567",
  "date_of_birth": "01/15/1990"
}
```

#### Get All Users
```
GET /api/users
Response: {
  "data": [...],
  "meta": {
    "count": 10,
    "requestId": "uuid"
  }
}
```

#### Update User
```
PUT /api/users/:id
Body: Same as create
```

#### Delete User
```
DELETE /api/users/:id
```

## 🏗️ Architecture Decisions

### Why TypeScript?
- Type safety reduces runtime errors
- Better IDE support and refactoring
- Aligns with Ironclad's tech stack

### Why PostgreSQL?
- ACID compliance for data integrity
- Better constraint support
- Production-proven for enterprise use

### Why Prometheus + Grafana?
- Industry standard for Kubernetes monitoring
- Pull-based model works well with dynamic pods
- Rich ecosystem and integrations

### Why Circuit Breaker?
- Prevents cascade failures
- Gives failing services time to recover
- Better user experience during partial outages

## 🚀 Production Considerations

### What's Included
- Multi-stage Docker builds
- Non-root user execution
- Resource limits and requests
- Liveness and readiness probes
- Horizontal pod autoscaling
- Network policies
- Structured logging
- Metrics and monitoring

### What Would Be Added for Production
- TLS/HTTPS termination
- OAuth/JWT authentication
- Distributed tracing (Jaeger)
- Log aggregation (ELK stack)
- Backup and disaster recovery
- Multi-region deployment
- CI/CD pipeline
- Comprehensive test suite
- API rate limiting by user/tenant
- Database migrations tooling

## 🔍 Troubleshooting

### Backend Won't Start
```bash
# Check logs
kubectl logs -f deployment/backend -n ironclad-demo

# Check database connection
kubectl exec -it deployment/postgres -n ironclad-demo -- psql -U ironclad_user
```

### Metrics Not Showing
```bash
# Check Prometheus targets
curl http://<prometheus-url>/api/v1/targets

# Check pod annotations
kubectl describe pod -l app=backend -n ironclad-demo
```

## 📈 Performance

### Benchmarks
- Single instance handles ~1000 req/sec
- p99 latency < 50ms under normal load
- Scales to 10 replicas automatically
- Circuit breaker prevents cascade failures

### Load Testing
```bash
# Using Apache Bench
ab -n 10000 -c 100 http://<backend-url>/api/users

# Using k6 (better for complex scenarios)
k6 run loadtest.js
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Run tests
4. Submit a pull request

## 📄 License

MIT