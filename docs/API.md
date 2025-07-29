# API Documentation - Ironclad SRE Demo

## 📋 Tabla de Contenidos
1. [Información General](#información-general)
2. [Autenticación](#autenticación)
3. [Formato de Respuestas](#formato-de-respuestas)
4. [Endpoints de Salud](#endpoints-de-salud)
5. [Endpoints de Usuarios](#endpoints-de-usuarios)
6. [Endpoints de Administración](#endpoints-de-administración)
7. [Códigos de Error](#códigos-de-error)
8. [Ejemplos de Uso](#ejemplos-de-uso)
9. [Rate Limiting](#rate-limiting)
10. [Monitoreo y Métricas](#monitoreo-y-métricas)

---

## 🌐 Información General

### Base URL
```
Desarrollo Local: http://localhost:3000
Producción: https://api.ironclad-demo.com
```

### Versión API
```
Versión: 1.0.0
Última actualización: 2023-12-07
```

### Content-Type
Todas las requests y responses usan JSON:
```http
Content-Type: application/json
```

### Headers Comunes
```http
Content-Type: application/json
X-Request-Id: <uuid>  # Agregado automáticamente para tracing
User-Agent: <client-info>
```

---

## 🔐 Autenticación

**Estado Actual**: No implementada (fuera del scope del demo)

**Implementación Futura**:
```http
Authorization: Bearer <jwt-token>
```

Para propósitos de demo, todos los endpoints son públicos con rate limiting.

---

## 📊 Formato de Respuestas

### Respuestas Exitosas
```json
{
  "data": { /* objeto o array con datos */ },
  "meta": {
    "requestId": "123e4567-e89b-12d3-a456-426614174000",
    "timestamp": "2023-12-07T10:30:00.000Z"
  }
}
```

### Respuestas de Error
```json
{
  "error": "Human readable error message",
  "requestId": "123e4567-e89b-12d3-a456-426614174000",
  "timestamp": "2023-12-07T10:30:00.000Z",
  "details": [  // Solo para validation errors
    {
      "field": "email",
      "message": "Email is required"
    }
  ]
}
```

### HTTP Status Codes
- `200 OK`: Operación exitosa
- `201 Created`: Recurso creado exitosamente
- `204 No Content`: Operación exitosa sin contenido
- `400 Bad Request`: Error de validación
- `404 Not Found`: Recurso no encontrado
- `409 Conflict`: Recurso ya existe (ej: email duplicado)
- `429 Too Many Requests`: Rate limit excedido
- `500 Internal Server Error`: Error interno del servidor
- `503 Service Unavailable`: Servicio temporalmente no disponible

---

## 🏥 Endpoints de Salud

### GET /health
**Propósito**: Health check básico para load balancers

**Request**:
```http
GET /health HTTP/1.1
Host: localhost:3000
```

**Response**: `200 OK`
```json
{
  "status": "healthy",
  "timestamp": "2023-12-07T10:30:00.000Z",
  "version": "1.0.0"
}
```

**Uso**: Load balancers y monitoring systems

---

### GET /ready
**Propósito**: Readiness check para Kubernetes

**Request**:
```http
GET /ready HTTP/1.1
Host: localhost:3000
```

**Response (Ready)**: `200 OK`
```json
{
  "status": "ready",
  "database": "connected",
  "timestamp": "2023-12-07T10:30:00.000Z"
}
```

**Response (Not Ready)**: `503 Service Unavailable`
```json
{
  "status": "not ready",
  "database": "disconnected",
  "timestamp": "2023-12-07T10:30:00.000Z"
}
```

**Uso**: Kubernetes readiness probes

---

### GET /metrics
**Propósito**: Métricas Prometheus para monitoring

**Request**:
```http
GET /metrics HTTP/1.1
Host: localhost:3000
```

**Response**: `200 OK`
```prometheus
# HELP http_requests_total Total number of HTTP requests
# TYPE http_requests_total counter
http_requests_total{method="GET",route="/api/users",status="200"} 1500
http_requests_total{method="POST",route="/api/users",status="201"} 300
http_requests_total{method="GET",route="/api/users",status="500"} 5

# HELP http_request_duration_seconds Duration of HTTP requests in seconds
# TYPE http_request_duration_seconds histogram
http_request_duration_seconds_bucket{method="GET",route="/api/users",le="0.1"} 1200
http_request_duration_seconds_bucket{method="GET",route="/api/users",le="0.5"} 1450
http_request_duration_seconds_bucket{method="GET",route="/api/users",le="1.0"} 1500

# HELP sli_availability Service Level Indicator for availability
# TYPE sli_availability gauge
sli_availability 0.9995

# HELP error_budget_remaining_percentage Remaining error budget as percentage
# TYPE error_budget_remaining_percentage gauge
error_budget_remaining_percentage 75
```

**Uso**: Scraping por Prometheus para alertas y dashboards

---

## 👥 Endpoints de Usuarios

### GET /api/users
**Propósito**: Obtener lista de todos los usuarios

**Request**:
```http
GET /api/users HTTP/1.1
Host: localhost:3000
```

**Response**: `200 OK`
```json
{
  "users": [
    {
      "id": "123e4567-e89b-12d3-a456-426614174000",
      "first_name": "John",
      "middle_name": "Michael",
      "last_name": "Doe",
      "email": "john.doe@example.com",
      "phone_number": "(555) 123-4567",
      "date_of_birth": "1990-05-15",
      "created_at": "2023-12-07T10:00:00.000Z",
      "updated_at": "2023-12-07T10:00:00.000Z"
    },
    {
      "id": "456e7890-e89b-12d3-a456-426614174001",
      "first_name": "Jane",
      "middle_name": null,
      "last_name": "Smith",
      "email": "jane.smith@example.com",
      "phone_number": "555-987-6543",
      "date_of_birth": "1985-03-22",
      "created_at": "2023-12-07T09:45:00.000Z",
      "updated_at": "2023-12-07T09:45:00.000Z"
    }
  ],
  "count": 2
}
```

**Características**:
- Ordenados por `created_at DESC` (más recientes primero)
- Include `count` para facilitar paginación futura
- Todos los campos son siempre incluidos (middle_name puede ser null)

---

### GET /api/users/:id
**Propósito**: Obtener un usuario específico por ID

**Parameters**:
- `id` (string, required): UUID del usuario

**Request**:
```http
GET /api/users/123e4567-e89b-12d3-a456-426614174000 HTTP/1.1
Host: localhost:3000
```

**Response (Found)**: `200 OK`
```json
{
  "id": "123e4567-e89b-12d3-a456-426614174000",
  "first_name": "John",
  "middle_name": "Michael",
  "last_name": "Doe",
  "email": "john.doe@example.com",
  "phone_number": "(555) 123-4567",
  "date_of_birth": "1990-05-15",
  "created_at": "2023-12-07T10:00:00.000Z",
  "updated_at": "2023-12-07T10:00:00.000Z"
}
```

**Response (Not Found)**: `404 Not Found`
```json
{
  "error": "User not found",
  "requestId": "123e4567-e89b-12d3-a456-426614174000",
  "timestamp": "2023-12-07T10:30:00.000Z"
}
```

---

### POST /api/users
**Propósito**: Crear un nuevo usuario

**Request Body**:
```json
{
  "first_name": "John",
  "middle_name": "Michael",     // Opcional
  "last_name": "Doe",
  "email": "john.doe@example.com",
  "phone_number": "(555) 123-4567",
  "date_of_birth": "05/15/1990"  // MM/DD/YYYY format
}
```

**Request**:
```http
POST /api/users HTTP/1.1
Host: localhost:3000
Content-Type: application/json

{
  "first_name": "John",
  "middle_name": "Michael",
  "last_name": "Doe",
  "email": "john.doe@example.com",
  "phone_number": "(555) 123-4567",
  "date_of_birth": "05/15/1990"
}
```

#### Reglas de Validación

| Campo | Requerido | Tipo | Validación | Ejemplo |
|-------|-----------|------|------------|---------|
| `first_name` | ✅ | string | 1-100 chars, solo letras/espacios/guiones | "John" |
| `middle_name` | ❌ | string | 0-100 chars, solo letras/espacios/guiones | "Michael" |
| `last_name` | ✅ | string | 1-100 chars, solo letras/espacios/guiones | "Doe" |
| `email` | ✅ | string | Formato email válido, max 255 chars, único | "john@example.com" |
| `phone_number` | ✅ | string | Formato teléfono US válido | "(555) 123-4567" |
| `date_of_birth` | ✅ | string | MM/DD/YYYY, fecha válida, no futuro | "05/15/1990" |

#### Formatos de Teléfono Aceptados
```javascript
// Todos estos formatos son válidos:
"(555) 123-4567"
"555-123-4567"
"555.123.4567"
"5551234567"
"+1 555 123 4567"
"1-555-123-4567"
```

#### Validación de Fecha
```javascript
// Válido: Fechas reales en formato MM/DD/YYYY
"05/15/1990"  // ✅ Mayo 15, 1990
"12/31/2000"  // ✅ Diciembre 31, 2000
"02/29/2020"  // ✅ Año bisiesto

// Inválido:
"13/01/1990"  // ❌ Mes 13 no existe
"02/30/1990"  // ❌ Febrero no tiene 30 días
"05/15/2025"  // ❌ Fecha en el futuro
"1990-05-15"  // ❌ Formato incorrecto
```

**Response (Success)**: `201 Created`
```json
{
  "id": "123e4567-e89b-12d3-a456-426614174000",
  "first_name": "John",
  "middle_name": "Michael",
  "last_name": "Doe",
  "email": "john.doe@example.com",
  "phone_number": "(555) 123-4567",
  "date_of_birth": "1990-05-15",  // Convertido a formato ISO
  "created_at": "2023-12-07T10:30:00.000Z",
  "updated_at": "2023-12-07T10:30:00.000Z"
}
```

**Response (Validation Error)**: `400 Bad Request`
```json
{
  "error": "Validation failed",
  "requestId": "123e4567-e89b-12d3-a456-426614174000",
  "timestamp": "2023-12-07T10:30:00.000Z",
  "details": [
    {
      "field": "email",
      "message": "Email is required"
    },
    {
      "field": "phone_number", 
      "message": "Invalid US phone number format"
    },
    {
      "field": "date_of_birth",
      "message": "Date of birth cannot be in the future"
    }
  ]
}
```

**Response (Duplicate Email)**: `409 Conflict`
```json
{
  "error": "Email already exists",
  "requestId": "123e4567-e89b-12d3-a456-426614174000",
  "timestamp": "2023-12-07T10:30:00.000Z"
}
```

---

### PUT /api/users/:id
**Propósito**: Actualizar un usuario existente

**Parameters**:
- `id` (string, required): UUID del usuario

**Request Body**: Igual que POST (todos los campos requeridos)
```json
{
  "first_name": "Jane",
  "middle_name": "Elizabeth", 
  "last_name": "Smith",
  "email": "jane.smith@example.com",
  "phone_number": "(555) 987-6543",
  "date_of_birth": "03/22/1985"
}
```

**Request**:
```http
PUT /api/users/123e4567-e89b-12d3-a456-426614174000 HTTP/1.1
Host: localhost:3000
Content-Type: application/json

{
  "first_name": "Jane",
  "middle_name": "Elizabeth",
  "last_name": "Smith", 
  "email": "jane.smith@example.com",
  "phone_number": "(555) 987-6543",
  "date_of_birth": "03/22/1985"
}
```

**Response (Success)**: `200 OK`
```json
{
  "id": "123e4567-e89b-12d3-a456-426614174000",
  "first_name": "Jane",
  "middle_name": "Elizabeth",
  "last_name": "Smith",
  "email": "jane.smith@example.com", 
  "phone_number": "(555) 987-6543",
  "date_of_birth": "1985-03-22",
  "created_at": "2023-12-07T10:00:00.000Z",
  "updated_at": "2023-12-07T10:35:00.000Z"  // Actualizado automáticamente
}
```

**Response (Not Found)**: `404 Not Found`
```json
{
  "error": "User not found",
  "requestId": "123e4567-e89b-12d3-a456-426614174000",
  "timestamp": "2023-12-07T10:30:00.000Z"
}
```

**Validación**: Mismas reglas que POST
**Nota**: `updated_at` se actualiza automáticamente via database trigger

---

### DELETE /api/users/:id
**Propósito**: Eliminar un usuario

**Parameters**:
- `id` (string, required): UUID del usuario

**Request**:
```http
DELETE /api/users/123e4567-e89b-12d3-a456-426614174000 HTTP/1.1
Host: localhost:3000
```

**Response (Success)**: `204 No Content`
```
(Sin body - solo status code)
```

**Response (Not Found)**: `404 Not Found`
```json
{
  "error": "User not found",
  "requestId": "123e4567-e89b-12d3-a456-426614174000",
  "timestamp": "2023-12-07T10:30:00.000Z"
}
```

**Nota**: Esta es una eliminación permanente (hard delete). En producción se consideraría soft delete.

---

## ⚙️ Endpoints de Administración

### POST /api/chaos
**Propósito**: Configurar chaos engineering (solo para testing)

**Request Body**:
```json
{
  "enabled": true,
  "errorRate": 0.1,      // 10% de requests fallarán
  "latencyMs": 1000,     // Máximo 1000ms de latencia adicional
  "latencyRate": 0.2     // 20% de requests tendrán latencia
}
```

**Request**:
```http
POST /api/chaos HTTP/1.1
Host: localhost:3000
Content-Type: application/json

{
  "enabled": true,
  "errorRate": 0.1,
  "latencyMs": 1000,
  "latencyRate": 0.2
}
```

**Response**: `200 OK`
```json
{
  "message": "Chaos configuration updated",
  "config": {
    "enabled": true,
    "errorRate": 0.1,
    "latencyMs": 1000,
    "latencyRate": 0.2
  }
}
```

**Uso**: Testing de resiliencia, validación de circuit breakers

---

### GET /api/circuit-breaker
**Propósito**: Obtener estado del circuit breaker

**Request**:
```http
GET /api/circuit-breaker HTTP/1.1
Host: localhost:3000
```

**Response**: `200 OK`
```json
{
  "database": {
    "state": "CLOSED",           // CLOSED | OPEN | HALF_OPEN
    "failures": 0,               // Número de fallos consecutivos
    "lastFailureTime": null      // Timestamp del último fallo
  }
}
```

**Estados del Circuit Breaker**:
- `CLOSED`: Funcionamiento normal, requests pasan
- `OPEN`: Fallando rápido, no intenta operaciones
- `HALF_OPEN`: Probando recovery, requests limitados

---

## ❌ Códigos de Error

### Error Responses Format
```json
{
  "error": "Human readable message",
  "requestId": "uuid-for-tracing", 
  "timestamp": "ISO-8601-timestamp",
  "details": [ /* array of validation errors */ ]
}
```

### Common Error Scenarios

#### 400 Bad Request - Validation Error
```json
{
  "error": "Validation failed",
  "requestId": "123e4567-e89b-12d3-a456-426614174000",
  "timestamp": "2023-12-07T10:30:00.000Z",
  "details": [
    {
      "field": "first_name",
      "message": "First name can only contain letters, spaces, and hyphens"
    },
    {
      "field": "email",
      "message": "Email is required"
    },
    {
      "field": "date_of_birth",
      "message": "Date must be in MM/DD/YYYY format"
    }
  ]
}
```

#### 404 Not Found
```json
{
  "error": "User not found",
  "requestId": "123e4567-e89b-12d3-a456-426614174000",
  "timestamp": "2023-12-07T10:30:00.000Z"
}
```

#### 409 Conflict - Duplicate Email
```json
{
  "error": "Email already exists", 
  "requestId": "123e4567-e89b-12d3-a456-426614174000",
  "timestamp": "2023-12-07T10:30:00.000Z"
}
```

#### 429 Too Many Requests
```json
{
  "error": "Too many requests",
  "requestId": "123e4567-e89b-12d3-a456-426614174000",
  "timestamp": "2023-12-07T10:30:00.000Z",
  "retryAfter": 900  // Seconds until rate limit resets
}
```

#### 500 Internal Server Error
```json
{
  "error": "Internal Server Error",
  "requestId": "123e4567-e89b-12d3-a456-426614174000", 
  "timestamp": "2023-12-07T10:30:00.000Z"
}
```

#### 503 Service Unavailable (Circuit Breaker)
```json
{
  "error": "Service temporarily unavailable",
  "requestId": "123e4567-e89b-12d3-a456-426614174000",
  "timestamp": "2023-12-07T10:30:00.000Z"
}
```

---

## 📝 Ejemplos de Uso

### Crear y Gestionar un Usuario (Happy Path)
```bash
# 1. Crear usuario
curl -X POST http://localhost:3000/api/users \
  -H "Content-Type: application/json" \
  -d '{
    "first_name": "John",
    "last_name": "Doe",
    "email": "john.doe@example.com",
    "phone_number": "(555) 123-4567", 
    "date_of_birth": "05/15/1990"
  }'

# Response: 201 Created con nuevo user object

# 2. Obtener todos los usuarios
curl http://localhost:3000/api/users

# Response: Array con todos los usuarios

# 3. Obtener usuario específico (usar ID del paso 1)
curl http://localhost:3000/api/users/123e4567-e89b-12d3-a456-426614174000

# Response: User object específico

# 4. Actualizar usuario
curl -X PUT http://localhost:3000/api/users/123e4567-e89b-12d3-a456-426614174000 \
  -H "Content-Type: application/json" \
  -d '{
    "first_name": "Jane",
    "last_name": "Smith", 
    "email": "jane.smith@example.com",
    "phone_number": "(555) 987-6543",
    "date_of_birth": "03/22/1985"
  }'

# Response: 200 OK con user object actualizado

# 5. Eliminar usuario
curl -X DELETE http://localhost:3000/api/users/123e4567-e89b-12d3-a456-426614174000

# Response: 204 No Content
```

### Testing de Validación
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
  }'

# Response: 400 Bad Request con detalles de validación

# Teléfono inválido
curl -X POST http://localhost:3000/api/users \
  -H "Content-Type: application/json" \
  -d '{
    "first_name": "John", 
    "last_name": "Doe",
    "email": "john@example.com",
    "phone_number": "123", 
    "date_of_birth": "05/15/1990"
  }'

# Response: 400 Bad Request

# Fecha futura
curl -X POST http://localhost:3000/api/users \
  -H "Content-Type: application/json" \
  -d '{
    "first_name": "John",
    "last_name": "Doe",
    "email": "john@example.com", 
    "phone_number": "(555) 123-4567",
    "date_of_birth": "12/31/2025"
  }'

# Response: 400 Bad Request
```

### Testing de Chaos Engineering
```bash
# Activar chaos con alto error rate
curl -X POST http://localhost:3000/api/chaos \
  -H "Content-Type: application/json" \
  -d '{"enabled": true, "errorRate": 0.5, "latencyRate": 0}'

# Hacer requests para ver errores
for i in {1..10}; do
  curl -s -o /dev/null -w "%{http_code}\n" http://localhost:3000/api/users
done

# Expected: Mix de 200 y 500 responses

# Verificar estado del circuit breaker
curl http://localhost:3000/api/circuit-breaker

# Expected: state cambiará a OPEN después de threshold failures

# Desactivar chaos
curl -X POST http://localhost:3000/api/chaos \
  -H "Content-Type: application/json" \
  -d '{"enabled": false}'
```

---

## 🚦 Rate Limiting

### Configuración Actual
- **Window**: 15 minutos
- **Limit**: 100 requests por IP por window
- **Scope**: Solo endpoints `/api/*`

### Headers de Rate Limiting
```http
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 95
X-RateLimit-Reset: 1607347200  # Unix timestamp
```

### Response cuando se excede el límite
```http
HTTP/1.1 429 Too Many Requests
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 0
X-RateLimit-Reset: 1607347200

{
  "error": "Too many requests",
  "requestId": "123e4567-e89b-12d3-a456-426614174000",
  "timestamp": "2023-12-07T10:30:00.000Z",
  "retryAfter": 900
}
```

### Testing Rate Limiting
```bash
# Script para probar rate limiting
for i in {1..150}; do
  response=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/api/users)
  echo "Request $i: $response"
  if [ "$response" == "429" ]; then
    echo "Rate limit reached at request $i"
    break
  fi
done

# Expected: Primeros 100 requests → 200, después → 429
```

---

## 📈 Monitoreo y Métricas

### Métricas Disponibles (Prometheus)

#### Request Metrics
```prometheus
# Total requests por endpoint y status
http_requests_total{method="GET",route="/api/users",status="200"} 1500

# Latencia de requests (histogram)
http_request_duration_seconds_bucket{method="POST",route="/api/users",le="0.1"} 245
http_request_duration_seconds_bucket{method="POST",route="/api/users",le="0.5"} 290
```

#### SLI Metrics
```prometheus
# Service Level Indicators
sli_availability 0.9995          # 99.95% availability
sli_latency_p99 0.150           # 150ms P99 latency
error_budget_remaining_percentage 75  # 75% error budget remaining
```

#### System Metrics
```prometheus
# Node.js process metrics
nodejs_heap_size_used_bytes 45000000
nodejs_heap_size_total_bytes 60000000
nodejs_eventloop_lag_seconds 0.001

# Custom application metrics
active_connections 12
db_connection_pool_size{state="active"} 5
db_connection_pool_size{state="idle"} 15
```

### Alertas Recomendadas
```yaml
# High error rate
- alert: HighErrorRate
  expr: rate(http_requests_total{status=~"5.."}[5m]) > 0.1
  for: 2m
  annotations:
    summary: "High error rate detected"

# Circuit breaker open
- alert: CircuitBreakerOpen
  expr: circuit_breaker_state{service="database"} == 1
  for: 0m
  annotations:
    summary: "Database circuit breaker is OPEN"

# SLO violation  
- alert: SLOViolation
  expr: sli_availability < 0.999
  for: 5m
  annotations:
    summary: "SLO availability violation"
```

### Log Structure
```json
{
  "level": "info",
  "message": "HTTP Request",
  "timestamp": "2023-12-07T10:30:00.000Z",
  "service": "ironclad-sre-demo",
  "version": "1.0.0", 
  "environment": "production",
  "requestId": "123e4567-e89b-12d3-a456-426614174000",
  "method": "POST",
  "url": "/api/users",
  "status": 201,
  "duration_ms": 145,
  "user_agent": "curl/7.68.0"
}
```

### Tracing
Cada request tiene un `X-Request-Id` header para correlación:
- Logs incluyen `requestId`
- Error responses incluyen `requestId`
- Facilita debugging y support

---

## 🔧 SDKs y Librerías Cliente

### JavaScript/TypeScript
```typescript
// Ejemplo de client wrapper
class IroncladApiClient {
  constructor(private baseUrl: string) {}

  async createUser(userData: CreateUserRequest): Promise<User> {
    const response = await fetch(`${this.baseUrl}/api/users`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(userData)
    });

    if (!response.ok) {
      const error = await response.json();
      throw new ApiError(error.error, error.requestId, response.status);
    }

    return response.json();
  }

  async getUsers(): Promise<User[]> {
    const response = await fetch(`${this.baseUrl}/api/users`);
    const data = await response.json();
    return data.users;
  }
}

// Uso
const client = new IroncladApiClient('http://localhost:3000');
const users = await client.getUsers();
```

### Python
```python
import requests
from typing import List, Dict, Optional

class IroncladApiClient:
    def __init__(self, base_url: str):
        self.base_url = base_url
        
    def create_user(self, user_data: Dict) -> Dict:
        response = requests.post(
            f"{self.base_url}/api/users",
            json=user_data
        )
        response.raise_for_status()
        return response.json()
        
    def get_users(self) -> List[Dict]:
        response = requests.get(f"{self.base_url}/api/users")
        response.raise_for_status()
        return response.json()["users"]

# Uso
client = IroncladApiClient("http://localhost:3000")
users = client.get_users()
```

---

## 📋 Changelog

### v1.0.0 (2023-12-07)
- ✅ CRUD completo para usuarios
- ✅ Validación exhaustiva de inputs
- ✅ Circuit breaker para resiliencia
- ✅ Chaos engineering para testing
- ✅ Métricas Prometheus
- ✅ Rate limiting
- ✅ Health checks
- ✅ Structured logging

### Próximas Versiones
- **v1.1.0**: Paginación y filtros
- **v1.2.0**: Autenticación JWT
- **v1.3.0**: Bulk operations
- **v2.0.0**: GraphQL support

---

## 📞 Soporte

### Desarrollo Local
- **URL**: http://localhost:3000
- **Logs**: `docker-compose logs backend`
- **Metrics**: http://localhost:3000/metrics
- **Health**: http://localhost:3000/health

### Issues y Bugs
- **GitHub**: [repository-url]/issues
- **Email**: sre-demo@ironclad.com
- **Slack**: #sre-demo-support

### Documentación Adicional
- **README.md**: Setup y deployment
- **docs/adrs/**: Architectural Decision Records
- **Grafana Dashboards**: http://localhost:3001 (admin/admin)

---

*Esta documentación está actualizada para la versión 1.0.0 del API. Para cambios y actualizaciones, consultar el changelog o issues en GitHub.*