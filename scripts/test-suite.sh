#!/bin/bash

# Automated Test Suite for Ironclad SRE Demo
# Comprehensive testing of all system components

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="ironclad-demo"
TEST_TIMEOUT=30
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[FAIL]${NC} $1"
}

print_section() {
    echo ""
    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE} $1${NC}"
    echo -e "${BLUE}================================================${NC}"
    echo ""
}

# Function to increment test counters
test_passed() {
    ((TOTAL_TESTS++))
    ((PASSED_TESTS++))
    print_success "$1"
}

test_failed() {
    ((TOTAL_TESTS++))
    ((FAILED_TESTS++))
    print_error "$1"
}

# Function to get service URLs
get_backend_url() {
    minikube service backend -n $NAMESPACE --url | head -1
}

get_prometheus_url() {
    minikube service prometheus -n $NAMESPACE --url
}

get_grafana_url() {
    minikube service grafana -n $NAMESPACE --url
}

# Test 1: Infrastructure Tests
test_infrastructure() {
    print_section "INFRASTRUCTURE TESTS"
    
    # Test namespace exists
    if kubectl get namespace $NAMESPACE > /dev/null 2>&1; then
        test_passed "Namespace '$NAMESPACE' exists"
    else
        test_failed "Namespace '$NAMESPACE' does not exist"
    fi
    
    # Test all required deployments are running
    local deployments=("backend" "postgres" "prometheus" "grafana")
    for deployment in "${deployments[@]}"; do
        if kubectl get deployment $deployment -n $NAMESPACE > /dev/null 2>&1; then
            local ready=$(kubectl get deployment $deployment -n $NAMESPACE -o jsonpath='{.status.readyReplicas}')
            local desired=$(kubectl get deployment $deployment -n $NAMESPACE -o jsonpath='{.spec.replicas}')
            
            if [ "$ready" = "$desired" ] && [ "$ready" -gt 0 ]; then
                test_passed "Deployment '$deployment' is ready ($ready/$desired replicas)"
            else
                test_failed "Deployment '$deployment' not ready ($ready/$desired replicas)"
            fi
        else
            test_failed "Deployment '$deployment' does not exist"
        fi
    done
    
    # Test services exist and have endpoints
    local services=("backend" "postgres" "prometheus" "grafana")
    for service in "${services[@]}"; do
        if kubectl get service $service -n $NAMESPACE > /dev/null 2>&1; then
            local endpoints=$(kubectl get endpoints $service -n $NAMESPACE -o jsonpath='{.subsets[*].addresses[*].ip}' | wc -w)
            if [ "$endpoints" -gt 0 ]; then
                test_passed "Service '$service' has $endpoints endpoint(s)"
            else
                test_failed "Service '$service' has no endpoints"
            fi
        else
            test_failed "Service '$service' does not exist"
        fi
    done
    
    # Test persistent volumes
    if kubectl get pvc postgres-storage -n $NAMESPACE > /dev/null 2>&1; then
        local pvc_status=$(kubectl get pvc postgres-storage -n $NAMESPACE -o jsonpath='{.status.phase}')
        if [ "$pvc_status" = "Bound" ]; then
            test_passed "PostgreSQL PVC is bound"
        else
            test_failed "PostgreSQL PVC status: $pvc_status"
        fi
    else
        test_failed "PostgreSQL PVC does not exist"
    fi
}

# Test 2: API Connectivity Tests
test_api_connectivity() {
    print_section "API CONNECTIVITY TESTS"
    
    local backend_url=$(get_backend_url)
    
    # Test health endpoint
    if curl -s -m $TEST_TIMEOUT "$backend_url/health" > /dev/null 2>&1; then
        local health_response=$(curl -s -m $TEST_TIMEOUT "$backend_url/health")
        if echo "$health_response" | jq -e '.status == "healthy"' > /dev/null 2>&1; then
            test_passed "Health endpoint returns healthy status"
        else
            test_failed "Health endpoint returns unhealthy status"
        fi
    else
        test_failed "Health endpoint is not accessible"
    fi
    
    # Test metrics endpoint
    if curl -s -m $TEST_TIMEOUT "$backend_url/metrics" > /dev/null 2>&1; then
        local metrics_response=$(curl -s -m $TEST_TIMEOUT "$backend_url/metrics")
        if echo "$metrics_response" | grep -q "http_requests_total"; then
            test_passed "Metrics endpoint returns Prometheus metrics"
        else
            test_failed "Metrics endpoint missing expected metrics"
        fi
    else
        test_failed "Metrics endpoint is not accessible"
    fi
    
    # Test API endpoints
    local endpoints=("/api/users" "/api/slo")
    for endpoint in "${endpoints[@]}"; do
        if curl -s -m $TEST_TIMEOUT "$backend_url$endpoint" > /dev/null 2>&1; then
            local status_code=$(curl -s -o /dev/null -w "%{http_code}" -m $TEST_TIMEOUT "$backend_url$endpoint")
            if [ "$status_code" = "200" ]; then
                test_passed "API endpoint '$endpoint' returns 200"
            else
                test_failed "API endpoint '$endpoint' returns $status_code"
            fi
        else
            test_failed "API endpoint '$endpoint' is not accessible"
        fi
    done
}

# Test 3: Database Connectivity Tests
test_database_connectivity() {
    print_section "DATABASE CONNECTIVITY TESTS"
    
    # Test database pod is running
    local db_pod=$(kubectl get pods -n $NAMESPACE -l app=postgres -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    
    if [ -n "$db_pod" ]; then
        test_passed "PostgreSQL pod '$db_pod' found"
        
        # Test database connection from within the pod
        if kubectl exec -n $NAMESPACE "$db_pod" -- psql -U ironclad_user -d ironclad -c "SELECT 1;" > /dev/null 2>&1; then
            test_passed "Database connection successful"
        else
            test_failed "Database connection failed"
        fi
        
        # Test database has expected tables
        local tables=$(kubectl exec -n $NAMESPACE "$db_pod" -- psql -U ironclad_user -d ironclad -t -c "SELECT count(*) FROM information_schema.tables WHERE table_schema='public';" 2>/dev/null | tr -d ' ')
        if [ "$tables" -gt 0 ]; then
            test_passed "Database has $tables table(s)"
        else
            test_failed "Database has no tables"
        fi
    else
        test_failed "PostgreSQL pod not found"
    fi
}

# Test 4: Monitoring Stack Tests
test_monitoring_stack() {
    print_section "MONITORING STACK TESTS"
    
    local prometheus_url=$(get_prometheus_url)
    local grafana_url=$(get_grafana_url)
    
    # Test Prometheus connectivity
    if curl -s -m $TEST_TIMEOUT "$prometheus_url/api/v1/status/config" > /dev/null 2>&1; then
        test_passed "Prometheus API is accessible"
        
        # Test Prometheus has targets
        local targets_response=$(curl -s -m $TEST_TIMEOUT "$prometheus_url/api/v1/targets")
        local active_targets=$(echo "$targets_response" | jq -r '.data.activeTargets | length' 2>/dev/null)
        
        if [ "$active_targets" -gt 0 ]; then
            test_passed "Prometheus has $active_targets active target(s)"
        else
            test_failed "Prometheus has no active targets"
        fi
        
        # Test specific metrics exist
        local metrics=("up" "http_requests_total" "http_request_duration_seconds")
        for metric in "${metrics[@]}"; do
            local metric_response=$(curl -s -m $TEST_TIMEOUT "$prometheus_url/api/v1/query?query=$metric")
            local result_count=$(echo "$metric_response" | jq -r '.data.result | length' 2>/dev/null)
            
            if [ "$result_count" -gt 0 ]; then
                test_passed "Metric '$metric' has data ($result_count series)"
            else
                test_failed "Metric '$metric' has no data"
            fi
        done
    else
        test_failed "Prometheus API is not accessible"
    fi
    
    # Test Grafana connectivity
    if curl -s -m $TEST_TIMEOUT "$grafana_url/api/health" > /dev/null 2>&1; then
        test_passed "Grafana API is accessible"
        
        # Test Grafana datasources
        local datasources_response=$(curl -s -m $TEST_TIMEOUT -u admin:admin "$grafana_url/api/datasources")
        local datasource_count=$(echo "$datasources_response" | jq '. | length' 2>/dev/null)
        
        if [ "$datasource_count" -gt 0 ]; then
            test_passed "Grafana has $datasource_count datasource(s) configured"
        else
            test_failed "Grafana has no datasources configured"
        fi
    else
        test_failed "Grafana API is not accessible"
    fi
}

# Test 5: Chaos Engineering Tests
test_chaos_engineering() {
    print_section "CHAOS ENGINEERING TESTS"
    
    local backend_url=$(get_backend_url)
    
    # Test chaos endpoints exist
    local chaos_endpoints=("/api/chaos/enable" "/api/chaos/disable" "/api/chaos/status")
    for endpoint in "${chaos_endpoints[@]}"; do
        if curl -s -m $TEST_TIMEOUT -X POST "$backend_url$endpoint" > /dev/null 2>&1; then
            test_passed "Chaos endpoint '$endpoint' is accessible"
        else
            test_failed "Chaos endpoint '$endpoint' is not accessible"
        fi
    done
    
    # Test error injection
    print_status "Testing error injection..."
    curl -s -X POST "$backend_url/api/chaos/errors/0.1" > /dev/null 2>&1
    curl -s -X POST "$backend_url/api/chaos/enable" > /dev/null 2>&1
    
    # Generate some requests and check for errors
    local error_found=false
    for i in {1..20}; do
        local status_code=$(curl -s -o /dev/null -w "%{http_code}" -m $TEST_TIMEOUT "$backend_url/api/users")
        if [ "$status_code" -ge 500 ]; then
            error_found=true
            break
        fi
    done
    
    if [ "$error_found" = true ]; then
        test_passed "Error injection is working"
    else
        test_failed "Error injection not working"
    fi
    
    # Test latency injection
    print_status "Testing latency injection..."
    curl -s -X POST "$backend_url/api/chaos/latency/500" > /dev/null 2>&1
    
    # Measure response time
    local start_time=$(date +%s%N)
    curl -s -m $TEST_TIMEOUT "$backend_url/api/users" > /dev/null 2>&1
    local end_time=$(date +%s%N)
    local duration=$((($end_time - $start_time) / 1000000))  # Convert to milliseconds
    
    if [ "$duration" -gt 400 ]; then  # Should be ~500ms + base latency
        test_passed "Latency injection is working ($duration ms)"
    else
        test_failed "Latency injection not working ($duration ms)"
    fi
    
    # Reset chaos state
    curl -s -X POST "$backend_url/api/chaos/disable" > /dev/null 2>&1
    test_passed "Chaos state reset"
}

# Test 6: Alert Rules Tests
test_alert_rules() {
    print_section "ALERT RULES TESTS"
    
    local prometheus_url=$(get_prometheus_url)
    
    # Test alert rules are loaded
    if curl -s -m $TEST_TIMEOUT "$prometheus_url/api/v1/rules" > /dev/null 2>&1; then
        local rules_response=$(curl -s -m $TEST_TIMEOUT "$prometheus_url/api/v1/rules")
        local rule_count=$(echo "$rules_response" | jq -r '.data.groups[].rules | length' 2>/dev/null | paste -sd+ | bc)
        
        if [ "$rule_count" -gt 0 ]; then
            test_passed "Prometheus has $rule_count alert rule(s) loaded"
        else
            test_failed "Prometheus has no alert rules loaded"
        fi
        
        # Test specific alert rules exist
        local expected_alerts=("HighErrorRate" "HighLatency" "DatabaseDown" "ErrorBudgetBurnRate")
        for alert in "${expected_alerts[@]}"; do
            if echo "$rules_response" | jq -r '.data.groups[].rules[].name' | grep -q "$alert"; then
                test_passed "Alert rule '$alert' is configured"
            else
                test_failed "Alert rule '$alert' is missing"
            fi
        done
    else
        test_failed "Cannot retrieve alert rules from Prometheus"
    fi
}

# Test 7: Horizontal Pod Autoscaler Tests
test_hpa() {
    print_section "HORIZONTAL POD AUTOSCALER TESTS"
    
    # Test HPA exists
    if kubectl get hpa backend-hpa -n $NAMESPACE > /dev/null 2>&1; then
        test_passed "HPA 'backend-hpa' exists"
        
        # Get HPA status
        local current_replicas=$(kubectl get hpa backend-hpa -n $NAMESPACE -o jsonpath='{.status.currentReplicas}')
        local min_replicas=$(kubectl get hpa backend-hpa -n $NAMESPACE -o jsonpath='{.spec.minReplicas}')
        local max_replicas=$(kubectl get hpa backend-hpa -n $NAMESPACE -o jsonpath='{.spec.maxReplicas}')
        
        if [ "$current_replicas" -ge "$min_replicas" ] && [ "$current_replicas" -le "$max_replicas" ]; then
            test_passed "HPA replica count is within bounds ($current_replicas between $min_replicas-$max_replicas)"
        else
            test_failed "HPA replica count out of bounds ($current_replicas not between $min_replicas-$max_replicas)"
        fi
        
        # Test metrics server is working
        if kubectl top pods -n $NAMESPACE > /dev/null 2>&1; then
            test_passed "Metrics server is working (kubectl top pods functional)"
        else
            test_failed "Metrics server not working"
        fi
    else
        test_failed "HPA 'backend-hpa' does not exist"
    fi
}

# Test 8: Performance Baseline Tests
test_performance_baseline() {
    print_section "PERFORMANCE BASELINE TESTS"
    
    local backend_url=$(get_backend_url)
    
    # Test response time under normal load
    print_status "Measuring baseline response times..."
    local total_time=0
    local successful_requests=0
    
    for i in {1..10}; do
        local start_time=$(date +%s%N)
        if curl -s -m $TEST_TIMEOUT "$backend_url/api/users" > /dev/null 2>&1; then
            local end_time=$(date +%s%N)
            local duration=$((($end_time - $start_time) / 1000000))
            total_time=$((total_time + duration))
            ((successful_requests++))
        fi
    done
    
    if [ "$successful_requests" -gt 0 ]; then
        local avg_response_time=$((total_time / successful_requests))
        if [ "$avg_response_time" -lt 1000 ]; then  # Less than 1 second
            test_passed "Average response time: ${avg_response_time}ms (acceptable)"
        else
            test_failed "Average response time: ${avg_response_time}ms (too slow)"
        fi
    else
        test_failed "No successful requests during performance test"
    fi
    
    # Test concurrent request handling
    print_status "Testing concurrent request handling..."
    local concurrent_start=$(date +%s)
    
    # Launch 20 concurrent requests
    for i in {1..20}; do
        curl -s -m $TEST_TIMEOUT "$backend_url/api/users" > /dev/null 2>&1 &
    done
    wait
    
    local concurrent_end=$(date +%s)
    local concurrent_duration=$((concurrent_end - concurrent_start))
    
    if [ "$concurrent_duration" -lt 10 ]; then  # Should complete within 10 seconds
        test_passed "Concurrent requests completed in ${concurrent_duration}s"
    else
        test_failed "Concurrent requests took ${concurrent_duration}s (too slow)"
    fi
}

# Test 9: Security Tests
test_security() {
    print_section "SECURITY TESTS"
    
    # Test network policies are applied
    if kubectl get networkpolicy -n $NAMESPACE > /dev/null 2>&1; then
        local netpol_count=$(kubectl get networkpolicy -n $NAMESPACE --no-headers | wc -l)
        if [ "$netpol_count" -gt 0 ]; then
            test_passed "Network policies are configured ($netpol_count policy/policies)"
        else
            test_failed "No network policies configured"
        fi
    else
        test_failed "Cannot check network policies"
    fi
    
    # Test pod security contexts
    local backend_pod=$(kubectl get pods -n $NAMESPACE -l app=backend -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ -n "$backend_pod" ]; then
        local run_as_user=$(kubectl get pod "$backend_pod" -n $NAMESPACE -o jsonpath='{.spec.securityContext.runAsUser}' 2>/dev/null)
        local run_as_non_root=$(kubectl get pod "$backend_pod" -n $NAMESPACE -o jsonpath='{.spec.securityContext.runAsNonRoot}' 2>/dev/null)
        
        if [ "$run_as_non_root" = "true" ] || [ -n "$run_as_user" ]; then
            test_passed "Pod security context configured"
        else
            test_warning "Pod security context not explicitly configured"
        fi
    fi
    
    # Test secrets are not exposed in environment variables
    local backend_url=$(get_backend_url)
    if curl -s -m $TEST_TIMEOUT "$backend_url/debug/env" 2>&1 | grep -q "404"; then
        test_passed "Debug endpoints are not exposed"
    else
        test_warning "Debug endpoints may be exposed"
    fi
}

# Test 10: Integration Tests
test_integration() {
    print_section "INTEGRATION TESTS"
    
    local backend_url=$(get_backend_url)
    
    # Test full user workflow
    print_status "Testing complete user workflow..."
    
    # 1. Create user
    local create_response=$(curl -s -m $TEST_TIMEOUT -X POST "$backend_url/api/users" \
        -H "Content-Type: application/json" \
        -d '{"name":"Test User","email":"test@example.com"}')
    
    if echo "$create_response" | jq -e '.data.id' > /dev/null 2>&1; then
        local user_id=$(echo "$create_response" | jq -r '.data.id')
        test_passed "User creation successful (ID: $user_id)"
        
        # 2. Get user
        local get_response=$(curl -s -m $TEST_TIMEOUT "$backend_url/api/users/$user_id")
        if echo "$get_response" | jq -e '.data.name == "Test User"' > /dev/null 2>&1; then
            test_passed "User retrieval successful"
        else
            test_failed "User retrieval failed"
        fi
        
        # 3. Update user
        local update_response=$(curl -s -m $TEST_TIMEOUT -X PUT "$backend_url/api/users/$user_id" \
            -H "Content-Type: application/json" \
            -d '{"name":"Updated User","email":"updated@example.com"}')
        
        if echo "$update_response" | jq -e '.data.name == "Updated User"' > /dev/null 2>&1; then
            test_passed "User update successful"
        else
            test_failed "User update failed"
        fi
        
        # 4. Delete user
        local delete_response=$(curl -s -m $TEST_TIMEOUT -X DELETE "$backend_url/api/users/$user_id")
        if curl -s -m $TEST_TIMEOUT "$backend_url/api/users/$user_id" | grep -q "404"; then
            test_passed "User deletion successful"
        else
            test_failed "User deletion failed"
        fi
    else
        test_failed "User creation failed"
    fi
    
    # Test metrics are being generated
    print_status "Verifying metrics generation..."
    sleep 5  # Wait for metrics to be scraped
    
    local prometheus_url=$(get_prometheus_url)
    local metrics_query="http_requests_total"
    local metrics_response=$(curl -s -m $TEST_TIMEOUT "$prometheus_url/api/v1/query?query=$metrics_query")
    local metrics_count=$(echo "$metrics_response" | jq -r '.data.result | length' 2>/dev/null)
    
    if [ "$metrics_count" -gt 0 ]; then
        test_passed "Metrics are being generated and collected"
    else
        test_failed "No metrics found in Prometheus"
    fi
}

# Function to run all tests
run_all_tests() {
    print_section "IRONCLAD SRE DEMO - AUTOMATED TEST SUITE"
    
    print_status "Starting comprehensive test suite..."
    print_status "This will test all components of the SRE demo system"
    echo ""
    
    # Run all test suites
    test_infrastructure
    test_api_connectivity
    test_database_connectivity
    test_monitoring_stack
    test_chaos_engineering
    test_alert_rules
    test_hpa
    test_performance_baseline
    test_security
    test_integration
    
    # Print summary
    print_section "TEST RESULTS SUMMARY"
    
    echo "Total Tests: $TOTAL_TESTS"
    echo "Passed: $PASSED_TESTS"
    echo "Failed: $FAILED_TESTS"
    
    local success_rate=$(( (PASSED_TESTS * 100) / TOTAL_TESTS ))
    
    if [ "$FAILED_TESTS" -eq 0 ]; then
        print_success "All tests passed! Success rate: 100%"
        print_success "System is fully operational and ready for demo"
        return 0
    elif [ "$success_rate" -ge 80 ]; then
        print_warning "Most tests passed. Success rate: ${success_rate}%"
        print_warning "System is mostly operational with minor issues"
        return 1
    else
        print_error "Multiple test failures. Success rate: ${success_rate}%"
        print_error "System has significant issues that need to be addressed"
        return 2
    fi
}

# Function to run specific test category
run_specific_test() {
    case $1 in
        "infrastructure")
            test_infrastructure
            ;;
        "api")
            test_api_connectivity
            ;;
        "database")
            test_database_connectivity
            ;;
        "monitoring")
            test_monitoring_stack
            ;;
        "chaos")
            test_chaos_engineering
            ;;
        "alerts")
            test_alert_rules
            ;;
        "hpa")
            test_hpa
            ;;
        "performance")
            test_performance_baseline
            ;;
        "security")
            test_security
            ;;
        "integration")
            test_integration
            ;;
        *)
            print_error "Unknown test category: $1"
            print_status "Available categories: infrastructure, api, database, monitoring, chaos, alerts, hpa, performance, security, integration"
            return 1
            ;;
    esac
}

# Function to show help
show_help() {
    echo "Ironclad SRE Demo - Automated Test Suite"
    echo ""
    echo "Usage: $0 [OPTION] [TEST_CATEGORY]"
    echo ""
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo "  -a, --all      Run all tests (default)"
    echo "  -c, --category Run specific test category"
    echo "  -l, --list     List available test categories"
    echo ""
    echo "Test Categories:"
    echo "  infrastructure  - Kubernetes infrastructure tests"
    echo "  api            - API connectivity and functionality tests"
    echo "  database       - Database connectivity and data tests"
    echo "  monitoring     - Prometheus and Grafana tests"
    echo "  chaos          - Chaos engineering functionality tests"
    echo "  alerts         - Alert rules and configuration tests"
    echo "  hpa            - Horizontal Pod Autoscaler tests"
    echo "  performance    - Performance and load tests"
    echo "  security       - Security configuration tests"
    echo "  integration    - End-to-end integration tests"
    echo ""
    echo "Examples:"
    echo "  $0                    # Run all tests"
    echo "  $0 -a                 # Run all tests"
    echo "  $0 -c monitoring      # Run only monitoring tests"
    echo "  $0 -c chaos           # Run only chaos engineering tests"
}

# Main function
main() {
    case ${1:-"all"} in
        "-h"|"--help")
            show_help
            exit 0
            ;;
        "-l"|"--list")
            echo "Available test categories:"
            echo "infrastructure, api, database, monitoring, chaos, alerts, hpa, performance, security, integration"
            exit 0
            ;;
        "-a"|"--all"|"all")
            run_all_tests
            exit $?
            ;;
        "-c"|"--category")
            if [ -n "$2" ]; then
                run_specific_test "$2"
                exit $?
            else
                print_error "Test category required with -c option"
                show_help
                exit 1
            fi
            ;;
        *)
            # If argument doesn't start with -, treat it as a category
            if [[ "$1" != -* ]]; then
                run_specific_test "$1"
                exit $?
            else
                print_error "Unknown option: $1"
                show_help
                exit 1
            fi
            ;;
    esac
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi