#!/bin/bash

# Ironclad SRE Demo Script
# This script demonstrates the complete SRE capabilities of the system

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="ironclad-demo"
DEMO_DURATION=300  # 5 minutes

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_section() {
    echo ""
    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE} $1${NC}"
    echo -e "${BLUE}================================================${NC}"
    echo ""
}

# Function to get backend URL
get_backend_url() {
    minikube service backend -n $NAMESPACE --url | head -1
}

# Function to get service URLs
get_service_urls() {
    local backend_url=$(get_backend_url)
    local prometheus_url=$(minikube service prometheus -n $NAMESPACE --url)
    local grafana_url=$(minikube service grafana -n $NAMESPACE --url)
    
    echo "Backend: $backend_url"
    echo "Prometheus: $prometheus_url"
    echo "Grafana: $grafana_url (admin/admin)"
}

# Function to wait for user input
wait_for_user() {
    echo ""
    read -p "Press Enter to continue..."
    echo ""
}

# Function to check service health
check_service_health() {
    local backend_url=$(get_backend_url)
    print_status "Checking service health..."
    
    if curl -s "$backend_url/health" | jq . > /dev/null 2>&1; then
        print_success "Service is healthy"
        curl -s "$backend_url/health" | jq .
    else
        print_error "Service is not responding"
        exit 1
    fi
}

# Function to generate baseline traffic
generate_baseline_traffic() {
    local backend_url=$(get_backend_url)
    print_status "Generating baseline traffic for 60 seconds..."
    
    for i in {1..60}; do
        # Successful requests (90%)
        for j in {1..9}; do
            curl -s "$backend_url/api/users" > /dev/null 2>&1 &
            curl -s "$backend_url/health" > /dev/null 2>&1 &
        done
        
        # Simulate some load
        sleep 1
        
        if [ $((i % 10)) -eq 0 ]; then
            print_status "Generated $i seconds of baseline traffic..."
        fi
    done
    
    wait
    print_success "Baseline traffic generation complete"
}

# Function to demonstrate chaos engineering
demonstrate_chaos_engineering() {
    local backend_url=$(get_backend_url)
    
    print_section "CHAOS ENGINEERING DEMONSTRATION"
    
    print_status "This demonstration will show:"
    echo "1. High Error Rate scenario"
    echo "2. High Latency scenario"
    echo "3. Circuit Breaker activation"
    echo "4. Recovery and monitoring"
    
    wait_for_user
    
    # Scenario 1: High Error Rate
    print_status "🔥 Scenario 1: Injecting 15% error rate..."
    curl -s -X POST "$backend_url/api/chaos/errors/0.15" > /dev/null
    curl -s -X POST "$backend_url/api/chaos/enable" > /dev/null
    
    print_success "Error injection enabled. Monitor Grafana dashboards."
    print_status "Generating traffic to trigger alerts..."
    
    # Generate traffic for 2 minutes
    for i in {1..120}; do
        curl -s "$backend_url/api/users" > /dev/null 2>&1 &
        curl -s "$backend_url/health" > /dev/null 2>&1 &
        sleep 0.5
    done
    wait
    
    print_warning "Check Prometheus alerts: rate(http_requests_total{status=~\"5..\"}[5m]) should be > 0.05"
    print_status "Alert should fire in ~5 minutes due to 'for: 5m' condition"
    
    wait_for_user
    
    # Scenario 2: High Latency
    print_status "🐌 Scenario 2: Adding 800ms latency..."
    curl -s -X POST "$backend_url/api/chaos/latency/800" > /dev/null
    
    print_success "Latency injection enabled. P95 latency should exceed 500ms threshold."
    
    # Generate traffic to show latency impact
    for i in {1..60}; do
        curl -s "$backend_url/api/users" > /dev/null 2>&1 &
        sleep 1
    done
    wait
    
    print_warning "Check Grafana: P95 latency should show ~800ms"
    
    wait_for_user
    
    # Scenario 3: Combined stress
    print_status "💥 Scenario 3: Combined high error rate + latency..."
    curl -s -X POST "$backend_url/api/chaos/errors/0.20" > /dev/null
    curl -s -X POST "$backend_url/api/chaos/latency/1000" > /dev/null
    
    print_success "Combined chaos enabled. System under maximum stress."
    
    # Generate heavy traffic
    for i in {1..90}; do
        for j in {1..5}; do
            curl -s "$backend_url/api/users" > /dev/null 2>&1 &
        done
        sleep 1
    done
    wait
    
    print_warning "Monitor the following:"
    echo "- Error rate should be ~20%"
    echo "- P95 latency should be ~1000ms"
    echo "- Both alerts should be firing"
    echo "- Error budget consumption should be visible"
    
    wait_for_user
    
    # Recovery
    print_status "🔧 Scenario 4: Recovery and healing..."
    curl -s -X POST "$backend_url/api/chaos/disable" > /dev/null
    
    print_success "Chaos engineering disabled. System should recover."
    
    # Generate clean traffic
    for i in {1..60}; do
        curl -s "$backend_url/api/users" > /dev/null 2>&1 &
        curl -s "$backend_url/health" > /dev/null 2>&1 &
        sleep 1
    done
    wait
    
    print_success "Recovery traffic generated. Metrics should return to normal."
    print_status "Alerts should auto-resolve once conditions clear."
}

# Function to demonstrate SLO monitoring
demonstrate_slo_monitoring() {
    local backend_url=$(get_backend_url)
    
    print_section "SLO MONITORING DEMONSTRATION"
    
    print_status "This demonstration shows:"
    echo "1. Error budget calculation"
    echo "2. Burn rate monitoring"
    echo "3. SLO vs SLI tracking"
    echo "4. Decision support metrics"
    
    wait_for_user
    
    print_status "Generating controlled error pattern to demonstrate error budget burn..."
    
    # Generate measured errors (5% error rate for controlled burn)
    for i in {1..180}; do  # 3 minutes
        # 19 successful requests
        for j in {1..19}; do
            curl -s "$backend_url/api/users" > /dev/null 2>&1 &
        done
        
        # 1 forced error (via chaos) - simulates 5% error rate
        if [ $((i % 20)) -eq 0 ]; then
            curl -s -X POST "$backend_url/api/chaos/errors/1.0" > /dev/null
            curl -s "$backend_url/api/users" > /dev/null 2>&1 &
            curl -s -X POST "$backend_url/api/chaos/disable" > /dev/null
        fi
        
        sleep 1
        
        if [ $((i % 30)) -eq 0 ]; then
            print_status "Generated $i seconds of measured error traffic..."
        fi
    done
    
    wait
    
    print_success "Controlled error pattern complete."
    print_status "Check the following metrics in Grafana:"
    echo "- Error budget remaining percentage"
    echo "- Error budget burn rate"
    echo "- SLO compliance tracking"
    echo "- Time to error budget exhaustion"
    
    wait_for_user
}

# Function to demonstrate auto-scaling
demonstrate_autoscaling() {
    print_section "AUTO-SCALING DEMONSTRATION"
    
    print_status "This demonstration shows:"
    echo "1. CPU-based horizontal pod autoscaling"
    echo "2. Load generation and scaling triggers"
    echo "3. Scale-up and scale-down behavior"
    echo "4. Resource monitoring during scaling"
    
    wait_for_user
    
    local backend_url=$(get_backend_url)
    
    print_status "Current pod count:"
    kubectl get pods -n $NAMESPACE -l app=backend
    
    print_status "HPA status:"
    kubectl get hpa -n $NAMESPACE
    
    wait_for_user
    
    print_status "🔥 Generating high CPU load to trigger scaling..."
    
    # Generate heavy computational load
    for i in {1..300}; do  # 5 minutes of load
        # Multiple concurrent requests to increase CPU usage
        for j in {1..20}; do
            curl -s "$backend_url/api/users" > /dev/null 2>&1 &
            curl -s "$backend_url/health" > /dev/null 2>&1 &
        done
        
        sleep 1
        
        if [ $((i % 30)) -eq 0 ]; then
            print_status "Load generation: $i/300 seconds"
            kubectl get hpa -n $NAMESPACE
            kubectl get pods -n $NAMESPACE -l app=backend --no-headers | wc -l | xargs echo "Current pod count:"
        fi
    done
    
    wait
    
    print_success "Load generation complete."
    print_status "Monitor the following:"
    echo "- HPA should show increased CPU usage"
    echo "- Pod count should have scaled up (may take 2-3 minutes)"
    echo "- Grafana should show increased resource usage"
    
    wait_for_user
    
    print_status "🔽 Allowing system to scale down..."
    print_status "Scale-down typically takes 5-10 minutes due to stabilization window."
    
    # Generate light load for scale-down
    for i in {1..120}; do  # 2 minutes of light load
        curl -s "$backend_url/health" > /dev/null 2>&1 &
        sleep 1
        
        if [ $((i % 30)) -eq 0 ]; then
            kubectl get hpa -n $NAMESPACE
        fi
    done
    
    print_status "Final HPA and pod status:"
    kubectl get hpa -n $NAMESPACE
    kubectl get pods -n $NAMESPACE -l app=backend
}

# Function to demonstrate monitoring and alerting
demonstrate_monitoring() {
    print_section "MONITORING & ALERTING DEMONSTRATION"
    
    print_status "This demonstration covers:"
    echo "1. Golden Signals monitoring"
    echo "2. Alert rule evaluation"
    echo "3. Dashboard navigation"
    echo "4. Troubleshooting workflows"
    
    wait_for_user
    
    local backend_url=$(get_backend_url)
    local prometheus_url=$(minikube service prometheus -n $NAMESPACE --url)
    local grafana_url=$(minikube service grafana -n $NAMESPACE --url)
    
    print_status "Service URLs for monitoring:"
    echo "Prometheus: $prometheus_url"
    echo "Grafana: $grafana_url (admin/admin)"
    
    print_status "Key metrics to observe:"
    echo "1. Request Rate: sum(rate(http_requests_total[5m]))"
    echo "2. Error Rate: sum(rate(http_requests_total{status=~\"5..\"}[5m])) / sum(rate(http_requests_total[5m]))"
    echo "3. Latency P95: histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))"
    echo "4. Saturation: CPU/Memory usage metrics"
    
    wait_for_user
    
    print_status "🔍 Testing Prometheus queries..."
    
    # Test basic connectivity
    if curl -s "$prometheus_url/api/v1/query?query=up" | jq . > /dev/null 2>&1; then
        print_success "Prometheus is accessible and responding"
    else
        print_error "Cannot connect to Prometheus"
    fi
    
    print_status "Current active alerts:"
    curl -s "$prometheus_url/api/v1/alerts" | jq '.data.alerts[] | {alertname: .labels.alertname, state: .state}' 2>/dev/null || echo "No alerts or connection issue"
    
    wait_for_user
    
    print_status "🎯 Navigate to the following Grafana dashboards:"
    echo "1. SRE Overview Dashboard - Golden signals and service health"
    echo "2. Infrastructure Metrics - Resource usage and Kubernetes metrics"
    echo "3. Business Metrics - Application-specific and business KPIs"
    
    print_status "Key dashboard features to explore:"
    echo "- Real-time metrics with 30s refresh"
    echo "- Alerting thresholds visualized as red lines"
    echo "- Error budget remaining gauge"
    echo "- Pod scaling and resource utilization"
    echo "- Circuit breaker status indicators"
}

# Function to run performance tests
run_performance_tests() {
    print_section "PERFORMANCE TESTING"
    
    local backend_url=$(get_backend_url)
    
    print_status "Running performance test suite..."
    
    # Test 1: Baseline performance
    print_status "Test 1: Baseline performance (1 req/sec for 30s)"
    for i in {1..30}; do
        time curl -s "$backend_url/api/users" > /dev/null
        sleep 1
    done
    
    # Test 2: Moderate load
    print_status "Test 2: Moderate load (10 req/sec for 30s)"
    for i in {1..30}; do
        for j in {1..10}; do
            curl -s "$backend_url/api/users" > /dev/null 2>&1 &
        done
        sleep 1
    done
    wait
    
    # Test 3: Burst load
    print_status "Test 3: Burst load (50 req/sec for 10s)"
    for i in {1..10}; do
        for j in {1..50}; do
            curl -s "$backend_url/api/users" > /dev/null 2>&1 &
        done
        sleep 1
    done
    wait
    
    print_success "Performance tests complete. Check Grafana for results."
}

# Main demo function
main() {
    print_section "IRONCLAD SRE DEMO STARTING"
    
    print_status "Welcome to the Ironclad SRE Demo!"
    print_status "This comprehensive demo will showcase:"
    echo "• Chaos Engineering capabilities"
    echo "• SLO monitoring and error budgets"
    echo "• Auto-scaling behavior"
    echo "• Monitoring and alerting"
    echo "• Performance testing"
    
    print_status "Demo will take approximately 20-30 minutes."
    print_status "Please have Grafana and Prometheus open in separate browser tabs."
    
    wait_for_user
    
    # Pre-flight checks
    print_status "Performing pre-flight checks..."
    
    if ! kubectl get namespace $NAMESPACE > /dev/null 2>&1; then
        print_error "Namespace $NAMESPACE not found. Please run 'make deploy' first."
        exit 1
    fi
    
    if ! kubectl get pods -n $NAMESPACE -l app=backend | grep -q Running; then
        print_error "Backend pods not running. Please check deployment status."
        exit 1
    fi
    
    print_success "Pre-flight checks passed."
    
    # Display service URLs
    print_status "Service URLs:"
    get_service_urls
    
    wait_for_user
    
    # Check service health
    check_service_health
    
    wait_for_user
    
    # Generate baseline traffic
    generate_baseline_traffic
    
    # Run demonstration scenarios
    demonstrate_chaos_engineering
    demonstrate_slo_monitoring
    demonstrate_autoscaling
    demonstrate_monitoring
    run_performance_tests
    
    print_section "DEMO COMPLETE"
    
    print_success "Ironclad SRE Demo completed successfully!"
    print_status "Summary of demonstrated capabilities:"
    echo "✅ Chaos Engineering with error and latency injection"
    echo "✅ SLO monitoring and error budget tracking"
    echo "✅ Horizontal Pod Autoscaling under load"
    echo "✅ Comprehensive monitoring with Golden Signals"
    echo "✅ Alerting and incident response workflows"
    echo "✅ Performance testing and analysis"
    
    print_status "Next steps:"
    echo "1. Explore the Grafana dashboards in detail"
    echo "2. Review Prometheus alerting rules"
    echo "3. Experiment with different chaos scenarios"
    echo "4. Test custom load patterns"
    
    print_status "To clean up the demo environment, run: make clean"
    
    echo ""
    print_success "Thank you for exploring the Ironclad SRE platform!"
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi