# Guía de Setup y Testing - Ironclad SRE Demo

## 📋 Tabla de Contenidos
1. [Pre-requisitos](#pre-requisitos)
2. [Instalación Local](#instalación-local)
3. [Ejecutar con Docker](#ejecutar-con-docker)
4. [Testing Funcional](#testing-funcional)
5. [Testing de Resiliencia](#testing-de-resiliencia)
6. [Monitoreo Local](#monitoreo-local)
7. [Troubleshooting](#troubleshooting)
8. [Scripts de Automatización](#scripts-de-automatización)

---

## 🔧 Pre-requisitos

### Software Requerido
```bash
# Versiones mínimas requeridas
Node.js: 18.x o superior
npm: 8.x o superior  
Docker: 20.x o superior
Docker Compose: 2.x o superior

# Opcional (para desarrollo sin Docker)
PostgreSQL: 15.x o superior
```

### Verificar Instalaciones
```bash
# Verificar versiones
node --version    # >=v18.0.0
npm --version     # >=8.0.0
docker --version  # >=20.0.0
docker-compose --version  # >=2.0.0

# Verificar Docker está corriendo
docker info
```

### Puertos Requeridos
Asegúrate que estos puertos estén disponibles:
```
3000  - Backend API
5432  - PostgreSQL
9090  - Métricas backend
9091  - Prometheus
3001  - Grafana
```

---

## 🚀 Instalación Local

### 1. Clonar y Preparar Proyecto
```bash
# Clonar repositorio
git clone <repository-url>
cd ironclad-sre-demo

# Verificar estructura
ls -la
# Debería mostrar:
# backend/
# docs/
# docker-compose.yml
# README.md
# .env.example
```

### 2. Configurar Environment Variables
```bash
# Copiar template de configuración
cp .env.example .env

# Editar configuración (opcional para desarrollo local)
nano .env
```

**Configuración por defecto** (funciona out-of-the-box):
```bash
# .env
DB_HOST=localhost
DB_PORT=5432
DB_NAME=ironclad_db
DB_USER=ironclad_user
DB_PASSWORD=changeme

NODE_ENV=development
PORT=3000
METRICS_PORT=9090

# Chaos Engineering (opcional)
CHAOS_ENABLED=false
CHAOS_ERROR_RATE=0
CHAOS_LATENCY_MS=0
CHAOS_LATENCY_RATE=0
```

### 3. Instalar Dependencies
```bash
# Instalar dependencias del backend
cd backend
npm install

# Verificar instalación exitosa
npm list --depth=0

# Regresar al directorio root
cd ..
```

---

## 🐳 Ejecutar con Docker

### Opción 1: Quick Start (Recomendado)
```bash
# Desde el directorio root del proyecto
docker-compose up --build

# Flags útiles:
# -d : Ejecutar en background
# --build : Rebuild images si hay cambios
# --force-recreate : Recrear containers

# Logs en tiempo real (si corriste con -d)
docker-compose logs -f backend
```

### Opción 2: Paso a Paso
```bash
# 1. Construir imagen del backend
docker-compose build backend

# 2. Iniciar solo la base de datos
docker-compose up -d postgres

# 3. Esperar que DB esté lista
docker-compose logs postgres
# Buscar: "database system is ready to accept connections"

# 4. Iniciar backend
docker-compose up backend

# 5. Iniciar monitoreo (opcional)
docker-compose up -d prometheus grafana
```

### Verificar que Todo Está Funcionando
```bash
# Health check del backend
curl http://localhost:3000/health
# Expected: {"status":"healthy","timestamp":"...","version":"1.0.0"}

# Database readiness
curl http://localhost:3000/ready
# Expected: {"status":"ready","database":"connected","timestamp":"..."}

# API funcional
curl http://localhost:3000/api/users
# Expected: {"users":[],"count":0}

# Métricas disponibles
curl http://localhost:3000/metrics | head -20
# Expected: Prometheus metrics format
```

---

## 🧪 Testing Funcional

### Test Suite Básico
```bash
# Script de testing completo
./test-api.sh

# O manualmente:
```

#### 1. Testing CRUD Happy Path
```bash
# Crear usuario
USER_ID=$(curl -s -X POST http://localhost:3000/api/users \
  -H "Content-Type: application/json" \
  -d '{
    "first_name": "John",
    "last_name": "Doe",
    "email": "john.doe@example.com",
    "phone_number": "(555) 123-4567",
    "date_of_birth": "05/15/1990"
  }' | jq -r '.id')

echo "Created user: $USER_ID"

# Verificar usuario creado
curl -s http://localhost:3000/api/users/$USER_ID | jq '.'

# Listar todos los usuarios
curl -s http://localhost:3000/api/users | jq '.count'

# Actualizar usuario
curl -s -X PUT http://localhost:3000/api/users/$USER_ID \
  -H "Content-Type: application/json" \
  -d '{
    "first_name": "Jane",
    "last_name": "Smith", 
    "email": "jane.smith@example.com",
    "phone_number": "(555) 987-6543",
    "date_of_birth": "03/22/1985"
  }' | jq '.first_name'

# Eliminar usuario
curl -s -X DELETE http://localhost:3000/api/users/$USER_ID
echo "User deleted"

# Verificar eliminación
curl -s http://localhost:3000/api/users/$USER_ID
# Expected: 404 Not Found
```

#### 2. Testing de Validación
```bash
# Email inválido
curl -X POST http://localhost:3000/api/users \
  -H "Content-Type: application/json" \
  -d '{
    "first_name": "John",
    "last_name": "Doe",
    "email": "invalid-email",
    "phone_number": "(555) 123-4567",
    "date_of_birth": "05/15/1990"
  }' | jq '.error'
# Expected: "Validation failed"

# Teléfono inválido  
curl -X POST http://localhost:3000/api/users \
  -H "Content-Type: application/json" \
  -d '{
    "first_name": "John",
    "last_name": "Doe",
    "email": "john@example.com",
    "phone_number": "123",
    "date_of_birth": "05/15/1990"
  }' | jq '.details[0].message'
# Expected: "Invalid US phone number format"

# Fecha futura
curl -X POST http://localhost:3000/api/users \
  -H "Content-Type: application/json" \
  -d '{
    "first_name": "John",
    "last_name": "Doe", 
    "email": "john@example.com",
    "phone_number": "(555) 123-4567",
    "date_of_birth": "12/31/2025"
  }' | jq '.details[0].message'
# Expected: "Date of birth cannot be in the future"

# Campos requeridos faltantes
curl -X POST http://localhost:3000/api/users \
  -H "Content-Type: application/json" \
  -d '{}' | jq '.details | length'
# Expected: >= 5 (validation errors)
```

#### 3. Testing Duplicate Email
```bash
# Crear primer usuario
curl -X POST http://localhost:3000/api/users \
  -H "Content-Type: application/json" \
  -d '{
    "first_name": "John",
    "last_name": "Doe",
    "email": "duplicate@example.com",
    "phone_number": "(555) 123-4567", 
    "date_of_birth": "05/15/1990"
  }'

# Intentar crear segundo usuario con mismo email
curl -X POST http://localhost:3000/api/users \
  -H "Content-Type: application/json" \
  -d '{
    "first_name": "Jane",
    "last_name": "Smith",
    "email": "duplicate@example.com",
    "phone_number": "(555) 987-6543",
    "date_of_birth": "03/22/1985"
  }' | jq '.error'
# Expected: "Email already exists"
```

---

## 🔥 Testing de Resiliencia

### 1. Circuit Breaker Testing
```bash
# Activar chaos con alto error rate
curl -X POST http://localhost:3000/api/chaos \
  -H "Content-Type: application/json" \
  -d '{"enabled": true, "errorRate": 0.8, "latencyRate": 0}'

echo "Chaos enabled - 80% error rate"

# Hacer requests para trigger circuit breaker
for i in {1..20}; do
  response=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/api/users)
  echo "Request $i: HTTP $response"
  
  # Check circuit breaker state periodically
  if [ $((i % 5)) -eq 0 ]; then
    state=$(curl -s http://localhost:3000/api/circuit-breaker | jq -r '.database.state')
    echo "  Circuit breaker state: $state"
  fi
  
  sleep 0.5
done

# Expected sequence:
# 1. First few requests: 200 OK
# 2. Then mixed 200/500 (chaos errors)
# 3. After 5 failures: Circuit breaker OPEN
# 4. Subsequent requests: 503 Service Unavailable (fail fast)

# Verificar estado final del circuit breaker
curl -s http://localhost:3000/api/circuit-breaker | jq '.'

# Desactivar chaos
curl -X POST http://localhost:3000/api/chaos \
  -H "Content-Type: application/json" \
  -d '{"enabled": false}'

echo "Waiting for circuit breaker recovery..."
sleep 65  # Wait for timeout (60s + buffer)

# Verificar recovery
curl -s http://localhost:3000/api/circuit-breaker | jq '.database.state'
# Expected: "HALF_OPEN" or "CLOSED"
```

### 2. Latency Injection Testing
```bash
# Configurar latency chaos
curl -X POST http://localhost:3000/api/chaos \
  -H "Content-Type: application/json" \
  -d '{"enabled": true, "errorRate": 0, "latencyMs": 3000, "latencyRate": 1}'

echo "All requests will have 0-3s additional latency"

# Test latency impact
for i in {1..5}; do
  echo "Request $i..."
  start_time=$(date +%s.%3N)
  
  curl -s http://localhost:3000/api/users > /dev/null
  
  end_time=$(date +%s.%3N)
  duration=$(echo "$end_time - $start_time" | bc)
  echo "  Duration: ${duration}s"
done

# Desactivar chaos
curl -X POST http://localhost:3000/api/chaos \
  -H "Content-Type: application/json" \
  -d '{"enabled": false}'
```

### 3. Rate Limiting Testing
```bash
# Test rate limiting (100 requests per 15 minutes)
echo "Testing rate limiting..."

for i in {1..120}; do
  response=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/api/users)
  
  if [ "$response" == "429" ]; then
    echo "Rate limit hit at request $i"
    break
  elif [ $((i % 10)) -eq 0 ]; then
    echo "Completed $i requests successfully"
  fi
done

# Expected: Rate limit around request 100-101
```

### 4. Database Connection Testing
```bash
# Simular database downtime
docker-compose stop postgres

echo "Database stopped - testing circuit breaker"

# Test API responses
for i in {1..10}; do
  response=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/api/users)
  echo "Request $i: HTTP $response"
  sleep 1
done

# Expected: Circuit breaker should open after failures

# Verificar readiness check
curl -s http://localhost:3000/ready | jq '.database'
# Expected: "disconnected"

# Health check should still work
curl -s http://localhost:3000/health | jq '.status'
# Expected: "healthy"

# Restaurar database
docker-compose start postgres

# Wait for database to be ready
echo "Waiting for database recovery..."
sleep 15

# Test recovery
curl -s http://localhost:3000/ready | jq '.database'
# Expected: "connected"
```

---

## 📊 Monitoreo Local

### Grafana Setup
```bash
# Grafana debería estar corriendo en puerto 3001
open http://localhost:3001

# Credenciales por defecto:
# Usuario: admin
# Password: admin

# Prometheus data source ya configurado en:
# URL: http://prometheus:9090
```

### Prometheus Queries Útiles
```bash
# Ver métricas disponibles
curl -s http://localhost:9091/api/v1/label/__name__/values | jq '.data[]' | grep ironclad

# Query examples:
# Rate of requests: rate(http_requests_total[5m])
# Error rate: rate(http_requests_total{status=~"5.."}[5m])
# Latency P95: histogram_quantile(0.95, http_request_duration_seconds_bucket)
# Active connections: active_connections
```

### Custom Metrics Exploration
```bash
# Backend metrics endpoint
curl -s http://localhost:3000/metrics | grep -E "(http_requests_total|http_request_duration|sli_|error_budget)"

# Specific metric queries
curl -s "http://localhost:9091/api/v1/query?query=http_requests_total" | jq '.data.result[0]'

curl -s "http://localhost:9091/api/v1/query?query=sli_availability" | jq '.data.result[0].value[1]'
```

### Log Analysis
```bash
# Backend logs
docker-compose logs backend | tail -20

# Filter error logs
docker-compose logs backend | grep '"level":"error"'

# Follow logs in real time
docker-compose logs -f backend | jq '.'

# Database logs
docker-compose logs postgres | tail -10
```

---

## 🔍 Troubleshooting

### Common Issues

#### 1. Puerto ya en uso
```bash
# Error: "port is already allocated"
# Solución: Identificar y matar proceso usando el puerto

# Para puerto 3000
lsof -ti:3000 | xargs kill -9

# Para puerto 5432
lsof -ti:5432 | xargs kill -9

# O cambiar puertos en docker-compose.yml
```

#### 2. Database connection fails
```bash
# Check si PostgreSQL está corriendo
docker-compose ps postgres

# Ver logs de PostgreSQL
docker-compose logs postgres

# Reiniciar database
docker-compose restart postgres

# Check database health desde adentro del container
docker-compose exec postgres pg_isready -U ironclad_user
```

#### 3. Backend no puede conectar a DB
```bash
# Check network connectivity
docker-compose exec backend ping postgres

# Check environment variables
docker-compose exec backend env | grep DB_

# Manual database test
docker-compose exec postgres psql -U ironclad_user -d ironclad_db -c "SELECT 1;"
```

#### 4. npm install falla
```bash
# Clear npm cache
npm cache clean --force

# Delete node_modules and package-lock.json
rm -rf backend/node_modules backend/package-lock.json

# Reinstall
cd backend && npm install
```

#### 5. Docker build issues
```bash
# Clear Docker cache
docker system prune -a

# Rebuild without cache
docker-compose build --no-cache backend

# Check Docker disk space
docker system df
```

### Debugging Commands

#### Application State
```bash
# Check all services status
docker-compose ps

# Backend health
curl -s http://localhost:3000/health | jq '.'

# Database readiness  
curl -s http://localhost:3000/ready | jq '.'

# Circuit breaker state
curl -s http://localhost:3000/api/circuit-breaker | jq '.'

# Current chaos configuration
curl -s http://localhost:3000/api/chaos | jq '.'
```

#### Performance Debugging
```bash
# Resource usage
docker stats

# Container processes
docker-compose exec backend ps aux

# Memory usage inside container
docker-compose exec backend free -h

# Disk usage
docker-compose exec backend df -h
```

#### Network Debugging
```bash
# Test connectivity between services
docker-compose exec backend ping postgres
docker-compose exec backend nc -zv postgres 5432

# Check open ports
docker-compose exec backend netstat -tlnp

# DNS resolution
docker-compose exec backend nslookup postgres
```

---

## 🤖 Scripts de Automatización

### test-api.sh
```bash
#!/bin/bash
# Complete API testing script

set -e

BASE_URL="http://localhost:3000"
TOTAL_TESTS=0
PASSED_TESTS=0

function test_endpoint() {
    local description="$1"
    local expected_status="$2"
    local curl_command="$3"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo "Testing: $description"
    
    actual_status=$(eval "$curl_command" 2>/dev/null | tail -1)
    
    if [ "$actual_status" == "$expected_status" ]; then
        echo "  ✅ PASS"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo "  ❌ FAIL (expected: $expected_status, got: $actual_status)"
    fi
    echo
}

# Health checks
test_endpoint "Health check" "200" "curl -s -o /dev/null -w '%{http_code}' $BASE_URL/health"
test_endpoint "Readiness check" "200" "curl -s -o /dev/null -w '%{http_code}' $BASE_URL/ready"

# CRUD operations
test_endpoint "Get empty users list" "200" "curl -s -o /dev/null -w '%{http_code}' $BASE_URL/api/users"
test_endpoint "Create valid user" "201" "curl -s -o /dev/null -w '%{http_code}' -X POST $BASE_URL/api/users -H 'Content-Type: application/json' -d '{\"first_name\":\"John\",\"last_name\":\"Doe\",\"email\":\"john@example.com\",\"phone_number\":\"(555) 123-4567\",\"date_of_birth\":\"05/15/1990\"}'"
test_endpoint "Create user with invalid email" "400" "curl -s -o /dev/null -w '%{http_code}' -X POST $BASE_URL/api/users -H 'Content-Type: application/json' -d '{\"first_name\":\"John\",\"last_name\":\"Doe\",\"email\":\"invalid\",\"phone_number\":\"(555) 123-4567\",\"date_of_birth\":\"05/15/1990\"}'"

# Summary
echo "Test Results: $PASSED_TESTS/$TOTAL_TESTS passed"
if [ $PASSED_TESTS -eq $TOTAL_TESTS ]; then
    echo "🎉 All tests passed!"
    exit 0
else
    echo "❌ Some tests failed"
    exit 1
fi
```

### chaos-test.sh
```bash
#!/bin/bash
# Chaos engineering test script

set -e

BASE_URL="http://localhost:3000"

echo "🎭 Starting Chaos Engineering Tests"

# Enable chaos
echo "Enabling chaos with 50% error rate..."
curl -s -X POST $BASE_URL/api/chaos \
  -H "Content-Type: application/json" \
  -d '{"enabled": true, "errorRate": 0.5, "latencyRate": 0}' > /dev/null

# Test requests with chaos
echo "Making 20 requests with chaos enabled..."
success_count=0
error_count=0

for i in {1..20}; do
    status=$(curl -s -o /dev/null -w "%{http_code}" $BASE_URL/api/users)
    if [ "$status" == "200" ]; then
        success_count=$((success_count + 1))
    else
        error_count=$((error_count + 1))
    fi
    
    if [ $((i % 5)) -eq 0 ]; then
        circuit_state=$(curl -s $BASE_URL/api/circuit-breaker | jq -r '.database.state')
        echo "  After $i requests: Circuit breaker is $circuit_state"
    fi
done

echo "Results: $success_count successes, $error_count errors"

# Disable chaos
echo "Disabling chaos..."
curl -s -X POST $BASE_URL/api/chaos \
  -H "Content-Type: application/json" \
  -d '{"enabled": false}' > /dev/null

echo "✅ Chaos testing completed"
```

### monitor.sh
```bash
#!/bin/bash
# Real-time monitoring script

BASE_URL="http://localhost:3000"

while true; do
    clear
    echo "🔍 Ironclad SRE Demo - Real-time Monitoring"
    echo "=========================================="
    echo "Timestamp: $(date)"
    echo
    
    # Health status
    health=$(curl -s $BASE_URL/health | jq -r '.status' 2>/dev/null || echo "ERROR")
    ready=$(curl -s $BASE_URL/ready | jq -r '.status' 2>/dev/null || echo "ERROR")
    echo "Health: $health | Ready: $ready"
    
    # Circuit breaker
    cb_state=$(curl -s $BASE_URL/api/circuit-breaker | jq -r '.database.state' 2>/dev/null || echo "ERROR")
    cb_failures=$(curl -s $BASE_URL/api/circuit-breaker | jq -r '.database.failures' 2>/dev/null || echo "ERROR")
    echo "Circuit Breaker: $cb_state (failures: $cb_failures)"
    
    # User count
    user_count=$(curl -s $BASE_URL/api/users | jq -r '.count' 2>/dev/null || echo "ERROR")
    echo "Users: $user_count"
    
    # Resource usage
    echo
    echo "Docker Container Stats:"
    docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" | head -4
    
    echo
    echo "Press Ctrl+C to exit"
    sleep 5
done
```

### Hacer Scripts Ejecutables
```bash
# Crear directorio de scripts
mkdir -p scripts

# Crear scripts (contenido arriba)
# Después hacer ejecutables:
chmod +x scripts/test-api.sh
chmod +x scripts/chaos-test.sh  
chmod +x scripts/monitor.sh

# Ejecutar
./scripts/test-api.sh
./scripts/chaos-test.sh
./scripts/monitor.sh
```

---

## 📈 Performance Testing

### Basic Load Testing con Apache Bench
```bash
# Install Apache Bench (si no está instalado)
# macOS: brew install httpie
# Ubuntu: sudo apt-get install apache2-utils

# Simple load test
ab -n 1000 -c 10 http://localhost:3000/api/users
# -n 1000: Total requests
# -c 10: Concurrent requests

# With POST data (crear usuarios)
ab -n 100 -c 5 -p user-data.json -T application/json http://localhost:3000/api/users

# user-data.json content:
echo '{
  "first_name": "Load",
  "last_name": "Test", 
  "email": "load.test@example.com",
  "phone_number": "(555) 123-4567",
  "date_of_birth": "01/01/1990"
}' > user-data.json
```

### Load Testing con wrk
```bash
# Install wrk
# macOS: brew install wrk
# Ubuntu: sudo apt-get install wrk

# Basic GET test
wrk -t12 -c400 -d30s http://localhost:3000/api/users
# -t12: 12 threads
# -c400: 400 connections  
# -d30s: 30 seconds duration

# POST test with Lua script
echo '
wrk.method = "POST"
wrk.body = "{\"first_name\":\"Load\",\"last_name\":\"Test\",\"email\":\"load.test@example.com\",\"phone_number\":\"(555) 123-4567\",\"date_of_birth\":\"01/01/1990\"}"
wrk.headers["Content-Type"] = "application/json"
' > post-script.lua

wrk -t4 -c100 -d10s -s post-script.lua http://localhost:3000/api/users
```

---

## 🎯 Conclusión

Esta guía te permite:

1. **✅ Setup completo** del entorno de desarrollo
2. **✅ Testing exhaustivo** de funcionalidad y resiliencia  
3. **✅ Monitoreo efectivo** del sistema
4. **✅ Debugging** de problemas comunes
5. **✅ Automatización** de testing repetitivo

### Next Steps
- Ejecutar todos los tests para validar el setup
- Explorar Grafana dashboards para entender métricas
- Experimentar con chaos engineering
- Revisar logs para entender el comportamiento del sistema

### Support
Si encuentras problemas:
1. Revisar la sección de [Troubleshooting](#troubleshooting)
2. Verificar logs con `docker-compose logs`
3. Consultar documentación adicional en `docs/`