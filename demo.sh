#!/bin/bash

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Ironclad SRE Excellence Demo ===${NC}"
echo ""

# Get service URLs
BACKEND_URL=$(minikube service backend -n ironclad-demo --url | head -1)
PROMETHEUS_URL=$(minikube service prometheus -n ironclad-demo --url)
GRAFANA_URL=$(minikube service grafana -n ironclad-demo --url)

echo -e "${YELLOW}Service URLs:${NC}"
echo "Backend: $BACKEND_URL"
echo "Prometheus: $PROMETHEUS_URL"
echo "Grafana: $GRAFANA_URL (admin/admin)"
echo ""

# Test health endpoint
echo -e "${YELLOW}1. Testing health endpoint...${NC}"
curl -s $BACKEND_URL/health | jq '.'
echo ""

# Create a user
echo -e "${YELLOW}2. Creating a test user...${NC}"
USER_DATA='{
  "first_name": "John",
  "middle_name": "Michael",
  "last_name": "Doe",
  "email": "john.doe@ironclad.com",
  "phone_number": "(555) 123-4567",
  "date_of_birth": "01/15/1990"
}'

RESPONSE=$(curl -s -X POST $BACKEND_URL/api/users \
  -H "Content-Type: application/json" \
  -d "$USER_DATA")

echo "$RESPONSE" | jq '.'
USER_ID=$(echo "$RESPONSE" | jq -r '.data.id')
echo ""

# Test input validation
echo -e "${YELLOW}3. Testing input validation (invalid email)...${NC}"
INVALID_DATA='{
  "first_name": "Jane",
  "last_name": "Smith",
  "email": "invalid-email",
  "phone_number": "(555) 987-6543",
  "date_of_birth": "12/25/1985"
}'

curl -s -X POST $BACKEND_URL/api/users \
  -H "Content-Type: application/json" \
  -d "$INVALID_DATA" | jq '.'
echo ""

# Get all users
echo -e "${YELLOW}4. Getting all users...${NC}"
curl -s $BACKEND_URL/api/users | jq '.'
echo ""

# Check metrics
echo -e "${YELLOW}5. Checking metrics endpoint...${NC}"
curl -s $BACKEND_URL/metrics | grep -E "http_requests_total|http_request_duration" | head -10
echo ""

# Demonstrate chaos engineering
echo -e "${YELLOW}6. Demonstrating chaos engineering...${NC}"
echo "Enabling chaos with 500ms latency..."
curl -s -X POST $BACKEND_URL/api/chaos/latency/500 | jq '.'

echo "Making a request with latency..."
time curl -s $BACKEND_URL/api/users | jq '.meta' || true
echo ""

echo "Disabling chaos..."
curl -s -X POST $BACKEND_URL/api/chaos/disable | jq '.'
echo ""

# Check SLOs
echo -e "${YELLOW}7. Checking SLOs...${NC}"
curl -s $BACKEND_URL/api/slo | jq '.'
echo ""

# Load test
echo -e "${YELLOW}8. Running mini load test...${NC}"
echo "Sending 50 requests..."
for i in {1..50}; do
  curl -s $BACKEND_URL/api/users > /dev/null &
done
wait
echo "Load test complete!"
echo ""

# Final metrics
echo -e "${YELLOW}9. Final metrics check...${NC}"
curl -s $BACKEND_URL/metrics | grep http_requests_total | tail -5
echo ""

echo -e "${GREEN}Demo complete! Check Grafana for visualizations.${NC}"
echo -e "${GREEN}Grafana URL: $GRAFANA_URL${NC}"