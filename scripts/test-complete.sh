#!/bin/bash
# Complete API testing script for Ironclad SRE Demo

set -e

BASE_URL="http://localhost:3000"
TOTAL_TESTS=0
PASSED_TESTS=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

function print_header() {
    echo -e "${BLUE}🧪 $1${NC}"
    echo "=================================="
}

function test_endpoint() {
    local description="$1"
    local expected_status="$2"
    local curl_command="$3"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo -n "Testing: $description... "
    
    actual_status=$(eval "$curl_command" 2>/dev/null)
    
    if [ "$actual_status" == "$expected_status" ]; then
        echo -e "${GREEN}✅ PASS${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}❌ FAIL${NC} (expected: $expected_status, got: $actual_status)"
    fi
}

function test_json_field() {
    local description="$1"
    local expected_value="$2"
    local curl_command="$3"
    local jq_filter="$4"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo -n "Testing: $description... "
    
    actual_value=$(eval "$curl_command" 2>/dev/null | jq -r "$jq_filter" 2>/dev/null)
    
    if [ "$actual_value" == "$expected_value" ]; then
        echo -e "${GREEN}✅ PASS${NC}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}❌ FAIL${NC} (expected: $expected_value, got: $actual_value)"
    fi
}

echo -e "${BLUE}🚀 Ironclad SRE Demo - Complete Test Suite${NC}"
echo "=============================================="
echo "Base URL: $BASE_URL"
echo "Timestamp: $(date)"
echo

# Wait for service to be ready
echo -e "${YELLOW}⏳ Waiting for service to be ready...${NC}"
for i in {1..30}; do
    if curl -s $BASE_URL/health > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Service is ready!${NC}"
        break
    fi
    if [ $i -eq 30 ]; then
        echo -e "${RED}❌ Service failed to start after 30 seconds${NC}"
        exit 1
    fi
    sleep 1
done
echo

# Health Check Tests
print_header "Health Check Tests"
test_endpoint "Health endpoint" "200" "curl -s -o /dev/null -w '%{http_code}' $BASE_URL/health"
test_json_field "Health status" "healthy" "curl -s $BASE_URL/health" ".status"
test_endpoint "Readiness endpoint" "200" "curl -s -o /dev/null -w '%{http_code}' $BASE_URL/ready"
test_json_field "Ready status" "ready" "curl -s $BASE_URL/ready" ".status"
test_endpoint "Metrics endpoint" "200" "curl -s -o /dev/null -w '%{http_code}' $BASE_URL/metrics"
echo

# Basic CRUD Tests
print_header "Basic CRUD Tests"
test_endpoint "Get empty users list" "200" "curl -s -o /dev/null -w '%{http_code}' $BASE_URL/api/users"
test_json_field "Empty users count" "0" "curl -s $BASE_URL/api/users" ".count"

# Create user
CREATE_RESPONSE=$(curl -s -X POST $BASE_URL/api/users \
  -H "Content-Type: application/json" \
  -d '{
    "first_name": "John",
    "last_name": "Doe",
    "email": "john.doe@example.com",
    "phone_number": "(555) 123-4567",
    "date_of_birth": "05/15/1990"
  }')

CREATE_STATUS=$(echo "$CREATE_RESPONSE" | jq -r 'if type == "object" and has("id") then "201" else "error" end')
test_endpoint "Create valid user" "201" "echo '$CREATE_STATUS'"

if [ "$CREATE_STATUS" == "201" ]; then
    USER_ID=$(echo "$CREATE_RESPONSE" | jq -r '.id')
    echo "  Created user ID: $USER_ID"
    
    # Test getting the created user
    test_endpoint "Get created user" "200" "curl -s -o /dev/null -w '%{http_code}' $BASE_URL/api/users/$USER_ID"
    test_json_field "User first name" "John" "curl -s $BASE_URL/api/users/$USER_ID" ".first_name"
    test_json_field "User email" "john.doe@example.com" "curl -s $BASE_URL/api/users/$USER_ID" ".email"
    
    # Test updating user
    test_endpoint "Update user" "200" "curl -s -o /dev/null -w '%{http_code}' -X PUT $BASE_URL/api/users/$USER_ID -H 'Content-Type: application/json' -d '{\"first_name\":\"Jane\",\"last_name\":\"Smith\",\"email\":\"jane.smith@example.com\",\"phone_number\":\"(555) 987-6543\",\"date_of_birth\":\"03/22/1985\"}'"
    test_json_field "Updated first name" "Jane" "curl -s $BASE_URL/api/users/$USER_ID" ".first_name"
    
    # Test deleting user
    test_endpoint "Delete user" "204" "curl -s -o /dev/null -w '%{http_code}' -X DELETE $BASE_URL/api/users/$USER_ID"
    test_endpoint "Get deleted user (404)" "404" "curl -s -o /dev/null -w '%{http_code}' $BASE_URL/api/users/$USER_ID"
else
    echo -e "${RED}⚠️  Skipping user-specific tests due to creation failure${NC}"
fi
echo

# Validation Tests
print_header "Input Validation Tests"
test_endpoint "Invalid email format" "400" "curl -s -o /dev/null -w '%{http_code}' -X POST $BASE_URL/api/users -H 'Content-Type: application/json' -d '{\"first_name\":\"John\",\"last_name\":\"Doe\",\"email\":\"invalid-email\",\"phone_number\":\"(555) 123-4567\",\"date_of_birth\":\"05/15/1990\"}'"

test_endpoint "Invalid phone format" "400" "curl -s -o /dev/null -w '%{http_code}' -X POST $BASE_URL/api/users -H 'Content-Type: application/json' -d '{\"first_name\":\"John\",\"last_name\":\"Doe\",\"email\":\"john@example.com\",\"phone_number\":\"123\",\"date_of_birth\":\"05/15/1990\"}'"

test_endpoint "Future date of birth" "400" "curl -s -o /dev/null -w '%{http_code}' -X POST $BASE_URL/api/users -H 'Content-Type: application/json' -d '{\"first_name\":\"John\",\"last_name\":\"Doe\",\"email\":\"john@example.com\",\"phone_number\":\"(555) 123-4567\",\"date_of_birth\":\"12/31/2025\"}'"

test_endpoint "Missing required fields" "400" "curl -s -o /dev/null -w '%{http_code}' -X POST $BASE_URL/api/users -H 'Content-Type: application/json' -d '{}'"

test_endpoint "Invalid name characters" "400" "curl -s -o /dev/null -w '%{http_code}' -X POST $BASE_URL/api/users -H 'Content-Type: application/json' -d '{\"first_name\":\"John123\",\"last_name\":\"Doe\",\"email\":\"john@example.com\",\"phone_number\":\"(555) 123-4567\",\"date_of_birth\":\"05/15/1990\"}'"
echo

# Duplicate Email Test
print_header "Duplicate Email Test"
# Create first user
curl -s -X POST $BASE_URL/api/users \
  -H "Content-Type: application/json" \
  -d '{
    "first_name": "First",
    "last_name": "User",
    "email": "duplicate@example.com",
    "phone_number": "(555) 111-1111",
    "date_of_birth": "01/01/1990"
  }' > /dev/null

# Try to create second user with same email
test_endpoint "Duplicate email rejection" "409" "curl -s -o /dev/null -w '%{http_code}' -X POST $BASE_URL/api/users -H 'Content-Type: application/json' -d '{\"first_name\":\"Second\",\"last_name\":\"User\",\"email\":\"duplicate@example.com\",\"phone_number\":\"(555) 222-2222\",\"date_of_birth\":\"02/02/1990\"}'"
echo

# Circuit Breaker Tests
print_header "Circuit Breaker Tests"
test_endpoint "Circuit breaker status" "200" "curl -s -o /dev/null -w '%{http_code}' $BASE_URL/api/circuit-breaker"
test_json_field "Circuit breaker initial state" "CLOSED" "curl -s $BASE_URL/api/circuit-breaker" ".database.state"
echo

# Chaos Engineering Tests
print_header "Chaos Engineering Tests"
test_endpoint "Chaos configuration endpoint" "200" "curl -s -o /dev/null -w '%{http_code}' -X POST $BASE_URL/api/chaos -H 'Content-Type: application/json' -d '{\"enabled\":false}'"

echo -e "${YELLOW}Testing chaos with 30% error rate...${NC}"
curl -s -X POST $BASE_URL/api/chaos \
  -H "Content-Type: application/json" \
  -d '{"enabled": true, "errorRate": 0.3, "latencyRate": 0}' > /dev/null

# Make requests with chaos enabled
success_count=0
error_count=0
for i in {1..10}; do
    status=$(curl -s -o /dev/null -w "%{http_code}" $BASE_URL/api/users)
    if [ "$status" == "200" ]; then
        success_count=$((success_count + 1))
    else
        error_count=$((error_count + 1))
    fi
done

echo "  Chaos results: $success_count successes, $error_count errors"
if [ $error_count -gt 0 ]; then
    echo -e "  ${GREEN}✅ Chaos engineering working${NC}"
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    echo -e "  ${YELLOW}⚠️  No chaos errors detected (may be random)${NC}"
fi
TOTAL_TESTS=$((TOTAL_TESTS + 1))

# Disable chaos
curl -s -X POST $BASE_URL/api/chaos \
  -H "Content-Type: application/json" \
  -d '{"enabled": false}' > /dev/null
echo

# Performance Test (Basic)
print_header "Basic Performance Test"
echo -e "${YELLOW}Running basic performance test (50 requests)...${NC}"
start_time=$(date +%s.%3N)
for i in {1..50}; do
    curl -s $BASE_URL/api/users > /dev/null
done
end_time=$(date +%s.%3N)
duration=$(echo "$end_time - $start_time" | bc)
rps=$(echo "scale=2; 50 / $duration" | bc)

echo "  Duration: ${duration}s"
echo "  Requests per second: $rps"

if (( $(echo "$rps > 10" | bc -l) )); then
    echo -e "  ${GREEN}✅ Performance acceptable (>10 RPS)${NC}"
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    echo -e "  ${RED}❌ Performance below threshold (<10 RPS)${NC}"
fi
TOTAL_TESTS=$((TOTAL_TESTS + 1))
echo

# Final Summary
echo "=============================================="
echo -e "${BLUE}📊 Test Results Summary${NC}"
echo "=============================================="
echo "Total Tests: $TOTAL_TESTS"
echo "Passed: $PASSED_TESTS"
echo "Failed: $((TOTAL_TESTS - PASSED_TESTS))"

success_rate=$(echo "scale=1; $PASSED_TESTS * 100 / $TOTAL_TESTS" | bc)
echo "Success Rate: $success_rate%"

if [ $PASSED_TESTS -eq $TOTAL_TESTS ]; then
    echo -e "${GREEN}🎉 All tests passed! System is working correctly.${NC}"
    exit 0
elif [ $PASSED_TESTS -gt $((TOTAL_TESTS * 8 / 10)) ]; then
    echo -e "${YELLOW}⚠️  Most tests passed, but some issues detected.${NC}"
    exit 1
else
    echo -e "${RED}❌ Multiple test failures detected. System needs attention.${NC}"
    exit 1
fi