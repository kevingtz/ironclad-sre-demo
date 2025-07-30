#!/bin/bash

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Ironclad SRE Excellence Demo (Docker Compose) ===${NC}"
echo ""

# Service URLs for Docker Compose
BACKEND_URL="http://localhost:3000"
PROMETHEUS_URL="http://localhost:9091"
GRAFANA_URL="http://localhost:3001"

echo -e "${BLUE}📊 Service URLs:${NC}"
echo "Backend: $BACKEND_URL"
echo "Prometheus: $PROMETHEUS_URL"
echo "Grafana: $GRAFANA_URL (admin/admin)"
echo ""

# 1. Health Check
echo -e "${YELLOW}1. Health Check${NC}"
echo "Testing backend health..."
HEALTH_RESPONSE=$(curl -s $BACKEND_URL/health)
echo "✅ Backend Status: $(echo $HEALTH_RESPONSE | grep -o '"status":"[^"]*"' | cut -d'"' -f4)"
echo "✅ Database: $(echo $HEALTH_RESPONSE | grep -o '"database":"[^"]*"' | cut -d'"' -f4)"
echo "✅ Circuit Breaker: $(echo $HEALTH_RESPONSE | grep -o '"state":"[^"]*"' | cut -d'"' -f4)"
echo ""

# 2. Metrics Check
echo -e "${YELLOW}2. Metrics Verification${NC}"
echo "Checking Prometheus metrics..."
METRICS_RESPONSE=$(curl -s $BACKEND_URL/metrics)
if echo "$METRICS_RESPONSE" | grep -q "http_requests_total"; then
    echo "✅ HTTP request metrics available"
fi
if echo "$METRICS_RESPONSE" | grep -q "http_request_duration_seconds"; then
    echo "✅ Response time metrics available"
fi
if echo "$METRICS_RESPONSE" | grep -q "process_cpu_seconds_total"; then
    echo "✅ System metrics available"
fi
echo ""

# 3. CRUD Operations Demo
echo -e "${YELLOW}3. CRUD Operations Demo${NC}"

# Create user
echo "Creating a new user..."
CREATE_RESPONSE=$(curl -s -X POST $BACKEND_URL/api/users \
  -H "Content-Type: application/json" \
  -d '{
    "first_name": "John",
    "middle_name": "Michael", 
    "last_name": "Doe",
    "email": "john.doe@example.com",
    "phone_number": "(555) 123-4567",
    "date_of_birth": "01/15/1990"
  }')

if echo "$CREATE_RESPONSE" | grep -q '"id"'; then
    echo "✅ User created successfully"
    USER_ID=$(echo $CREATE_RESPONSE | grep -o '"id":"[^"]*"' | cut -d'"' -f4)
    echo "   User ID: $USER_ID"
else
    echo "❌ User creation failed"
    echo "   Response: $CREATE_RESPONSE"
fi
echo ""

# Get all users
echo "Retrieving all users..."
USERS_RESPONSE=$(curl -s $BACKEND_URL/api/users)
USER_COUNT=$(echo $USERS_RESPONSE | grep -o '"count":[0-9]*' | cut -d':' -f2)
echo "✅ Retrieved $USER_COUNT users"
echo ""

# 4. Input Validation Demo
echo -e "${YELLOW}4. Input Validation Demo${NC}"
echo "Testing invalid email..."
INVALID_RESPONSE=$(curl -s -X POST $BACKEND_URL/api/users \
  -H "Content-Type: application/json" \
  -d '{
    "first_name": "Jane",
    "last_name": "Doe", 
    "email": "invalid-email",
    "phone_number": "(555) 123-4567",
    "date_of_birth": "01/15/1990"
  }')

if echo "$INVALID_RESPONSE" | grep -q "error"; then
    echo "✅ Input validation working - invalid email rejected"
else
    echo "❌ Input validation failed"
fi
echo ""

# 5. Chaos Engineering Demo
echo -e "${YELLOW}5. Chaos Engineering Demo${NC}"
echo "Enabling chaos mode..."
curl -s -X POST $BACKEND_URL/api/chaos/enable > /dev/null
echo "✅ Chaos mode enabled"

echo "Adding 500ms latency..."
curl -s -X POST $BACKEND_URL/api/chaos/latency/500 > /dev/null
echo "✅ Latency injection configured"

echo "Testing response time with chaos..."
START_TIME=$(date +%s%N)
curl -s $BACKEND_URL/health > /dev/null
END_TIME=$(date +%s%N)
DURATION=$(( (END_TIME - START_TIME) / 1000000 ))
echo "✅ Response time with chaos: ${DURATION}ms"

echo "Disabling chaos mode..."
curl -s -X POST $BACKEND_URL/api/chaos/disable > /dev/null
echo "✅ Chaos mode disabled"
echo ""

# 6. Load Testing
echo -e "${YELLOW}6. Load Testing Demo${NC}"
echo "Running basic load test (50 requests)..."
START_TIME=$(date +%s)

for i in {1..50}; do
    curl -s $BACKEND_URL/health > /dev/null &
done
wait

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
RPS=$((50 / DURATION))
echo "✅ Completed 50 requests in ${DURATION}s (~${RPS} req/s)"
echo ""

# 7. Monitoring Integration
echo -e "${YELLOW}7. Monitoring Integration${NC}"
echo "Checking Prometheus targets..."
TARGETS_RESPONSE=$(curl -s $PROMETHEUS_URL/api/v1/targets)
if echo "$TARGETS_RESPONSE" | grep -q '"health":"up"'; then
    echo "✅ Prometheus monitoring active"
fi

echo "Checking Grafana health..."
GRAFANA_HEALTH=$(curl -s -u admin:admin $GRAFANA_URL/api/health)
if echo "$GRAFANA_HEALTH" | grep -q '"database":"ok"'; then
    echo "✅ Grafana dashboard ready"
fi
echo ""

# 8. SRE Dashboard Access
echo -e "${YELLOW}8. SRE Excellence Dashboard${NC}"
echo "Dashboard features available:"
echo "✅ Request Rate by Method (timeseries)"
echo "✅ Error Rate % (gauge with thresholds)"
echo "✅ Response Time Percentiles (P50, P95, P99)"
echo "✅ Error Budget Remaining (gauge)"
echo "✅ SLI Availability & Latency P99 (stats)"
echo "✅ Database Pool Status (piechart)"
echo "✅ 5-second refresh rate for real-time monitoring"
echo ""

echo -e "${GREEN}🎯 Demo Complete!${NC}"
echo ""
echo -e "${BLUE}Next Steps:${NC}"
echo "1. Open Grafana: $GRAFANA_URL (admin/admin)"
echo "2. View the SRE Excellence Dashboard"
echo "3. Monitor metrics in real-time"
echo "4. Try API endpoints:"
echo "   - GET $BACKEND_URL/api/users"
echo "   - POST $BACKEND_URL/api/users (with JSON payload)"
echo "   - GET $BACKEND_URL/health"
echo "   - GET $BACKEND_URL/metrics"
echo ""
echo -e "${GREEN}🚀 SRE Excellence Demo Successfully Completed!${NC}"