#!/bin/bash

# Chaos Engineering Scenarios Script
# Provides specific chaos testing scenarios for the Ironclad SRE Demo

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="ironclad-demo"

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

# Function to check if service is available
check_service() {
    local backend_url=$(get_backend_url)
    if ! curl -s "$backend_url/health" > /dev/null 2>&1; then
        print_error "Backend service is not available. Please ensure the system is deployed."
        print_status "Run 'make deploy' to deploy the system first."
        exit 1
    fi
    print_success "Backend service is available at: $backend_url"
}

# Function to reset chaos state
reset_chaos() {
    local backend_url=$(get_backend_url)
    print_status "Resetting chaos engineering state..."
    curl -s -X POST "$backend_url/api/chaos/disable" > /dev/null
    print_success "Chaos engineering disabled. System should return to normal state."
}

# Scenario 1: Error Rate Testing
scenario_error_rate() {
    print_section "SCENARIO 1: ERROR RATE TESTING"
    
    local backend_url=$(get_backend_url)
    
    print_status "This scenario demonstrates:"
    echo "• Gradual error rate increase"
    echo "• Alert threshold testing"
    echo "• Error budget consumption"
    echo "• Recovery patterns"
    
    echo ""
    read -p "Press Enter to start the error rate scenario..."
    echo ""
    
    # Reset first
    reset_chaos
    sleep 5
    
    # Phase 1: Low error rate (1%)
    print_status "Phase 1: Injecting 1% error rate..."
    curl -s -X POST "$backend_url/api/chaos/errors/0.01" > /dev/null
    curl -s -X POST "$backend_url/api/chaos/enable" > /dev/null
    
    # Generate traffic for 2 minutes
    print_status "Generating traffic for 2 minutes..."
    for i in {1..120}; do
        curl -s "$backend_url/api/users" > /dev/null 2>&1 &
        curl -s "$backend_url/health" > /dev/null 2>&1 &
        if [ $((i % 30)) -eq 0 ]; then
            print_status "Traffic generation: $i/120 seconds (1% error rate)"
        fi
        sleep 1
    done
    wait
    
    print_success "Phase 1 complete. 1% error rate should be visible in metrics."
    
    # Phase 2: Medium error rate (3%)
    print_status "Phase 2: Increasing to 3% error rate..."
    curl -s -X POST "$backend_url/api/chaos/errors/0.03" > /dev/null
    
    for i in {1..120}; do
        curl -s "$backend_url/api/users" > /dev/null 2>&1 &
        curl -s "$backend_url/health" > /dev/null 2>&1 &
        if [ $((i % 30)) -eq 0 ]; then
            print_status "Traffic generation: $i/120 seconds (3% error rate)"
        fi
        sleep 1
    done
    wait
    
    print_success "Phase 2 complete. 3% error rate should be approaching alert threshold."
    
    # Phase 3: High error rate (7%) - Should trigger alert
    print_status "Phase 3: Increasing to 7% error rate (above 5% threshold)..."
    curl -s -X POST "$backend_url/api/chaos/errors/0.07" > /dev/null
    
    print_warning "This should trigger the HighErrorRate alert in ~5 minutes."
    
    for i in {1..300}; do  # 5 minutes
        curl -s "$backend_url/api/users" > /dev/null 2>&1 &
        curl -s "$backend_url/health" > /dev/null 2>&1 &
        if [ $((i % 60)) -eq 0 ]; then
            print_status "Traffic generation: $i/300 seconds (7% error rate - ALERT SHOULD FIRE)"
        fi
        sleep 1
    done
    wait
    
    print_warning "Check Prometheus alerts - HighErrorRate should be FIRING"
    
    # Phase 4: Recovery
    print_status "Phase 4: Returning to normal operations..."
    reset_chaos
    
    for i in {1..120}; do
        curl -s "$backend_url/api/users" > /dev/null 2>&1 &
        curl -s "$backend_url/health" > /dev/null 2>&1 &
        if [ $((i % 30)) -eq 0 ]; then
            print_status "Recovery traffic: $i/120 seconds (normal operations)"
        fi
        sleep 1
    done
    wait
    
    print_success "Error rate scenario complete. Alert should resolve in ~5 minutes."
}

# Scenario 2: Latency Testing
scenario_latency() {
    print_section "SCENARIO 2: LATENCY TESTING"
    
    local backend_url=$(get_backend_url)
    
    print_status "This scenario demonstrates:"
    echo "• Progressive latency increases"
    echo "• P95 latency monitoring"
    echo "• User experience impact simulation"
    echo "• Performance degradation alerts"
    
    echo ""
    read -p "Press Enter to start the latency scenario..."
    echo ""
    
    reset_chaos
    sleep 5
    
    # Phase 1: Mild latency (200ms)
    print_status "Phase 1: Adding 200ms latency..."
    curl -s -X POST "$backend_url/api/chaos/latency/200" > /dev/null
    curl -s -X POST "$backend_url/api/chaos/enable" > /dev/null
    
    for i in {1..90}; do
        curl -s "$backend_url/api/users" > /dev/null 2>&1 &
        if [ $((i % 30)) -eq 0 ]; then
            print_status "Latency test: $i/90 seconds (200ms added latency)"
        fi
        sleep 1
    done
    wait
    
    print_success "Phase 1 complete. P95 should show ~200ms latency."
    
    # Phase 2: Moderate latency (400ms)
    print_status "Phase 2: Increasing to 400ms latency..."
    curl -s -X POST "$backend_url/api/chaos/latency/400" > /dev/null
    
    for i in {1..90}; do
        curl -s "$backend_url/api/users" > /dev/null 2>&1 &
        if [ $((i % 30)) -eq 0 ]; then
            print_status "Latency test: $i/90 seconds (400ms added latency)"
        fi
        sleep 1
    done
    wait
    
    print_success "Phase 2 complete. P95 should show ~400ms latency."
    
    # Phase 3: High latency (700ms) - Should trigger alert
    print_status "Phase 3: Increasing to 700ms latency (above 500ms threshold)..."
    curl -s -X POST "$backend_url/api/chaos/latency/700" > /dev/null
    
    print_warning "This should trigger the HighLatency alert in ~5 minutes."
    
    for i in {1..300}; do  # 5 minutes
        curl -s "$backend_url/api/users" > /dev/null 2>&1 &
        if [ $((i % 60)) -eq 0 ]; then
            print_status "Latency test: $i/300 seconds (700ms - ALERT SHOULD FIRE)"
        fi
        sleep 1
    done
    wait
    
    print_warning "Check Prometheus alerts - HighLatency should be FIRING"
    
    # Phase 4: Recovery
    print_status "Phase 4: Returning to normal latency..."
    reset_chaos
    
    for i in {1..120}; do
        curl -s "$backend_url/api/users" > /dev/null 2>&1 &
        if [ $((i % 30)) -eq 0 ]; then
            print_status "Recovery test: $i/120 seconds (normal latency)"
        fi
        sleep 1
    done
    wait
    
    print_success "Latency scenario complete. Alert should resolve in ~5 minutes."
}

# Scenario 3: Combined Stress Test
scenario_combined_stress() {
    print_section "SCENARIO 3: COMBINED STRESS TEST"
    
    local backend_url=$(get_backend_url)
    
    print_status "This scenario demonstrates:"
    echo "• Multiple failure modes simultaneously"
    echo "• System behavior under extreme stress"
    echo "• Alert correlation and escalation"
    echo "• Recovery under compound failures"
    
    echo ""
    read -p "Press Enter to start the combined stress scenario..."
    echo ""
    
    reset_chaos
    sleep 5
    
    # Phase 1: Gradual stress buildup
    print_status "Phase 1: Building up stress gradually..."
    
    # Start with moderate errors and latency
    curl -s -X POST "$backend_url/api/chaos/errors/0.03" > /dev/null
    curl -s -X POST "$backend_url/api/chaos/latency/300" > /dev/null
    curl -s -X POST "$backend_url/api/chaos/enable" > /dev/null
    
    for i in {1..120}; do
        # Generate higher traffic volume
        for j in {1..3}; do
            curl -s "$backend_url/api/users" > /dev/null 2>&1 &
        done
        if [ $((i % 30)) -eq 0 ]; then
            print_status "Stress buildup: $i/120 seconds (3% errors + 300ms latency)"
        fi
        sleep 1
    done
    wait
    
    # Phase 2: Maximum stress
    print_status "Phase 2: Applying maximum stress..."
    curl -s -X POST "$backend_url/api/chaos/errors/0.15" > /dev/null
    curl -s -X POST "$backend_url/api/chaos/latency/1000" > /dev/null
    
    print_warning "Both HighErrorRate and HighLatency alerts should fire!"
    
    for i in {1..240}; do  # 4 minutes of max stress
        # High traffic volume to amplify effects
        for j in {1..5}; do
            curl -s "$backend_url/api/users" > /dev/null 2>&1 &
        done
        if [ $((i % 60)) -eq 0 ]; then
            print_status "Maximum stress: $i/240 seconds (15% errors + 1000ms latency)"
        fi
        sleep 1
    done
    wait
    
    print_warning "System should be showing:"
    echo "• Error rate: ~15% (3x threshold)"
    echo "• P95 latency: ~1000ms (2x threshold)"
    echo "• Multiple alerts firing"
    echo "• Significant error budget consumption"
    
    # Phase 3: Gradual recovery
    print_status "Phase 3: Gradual recovery..."
    
    # Reduce to moderate stress
    curl -s -X POST "$backend_url/api/chaos/errors/0.02" > /dev/null
    curl -s -X POST "$backend_url/api/chaos/latency/200" > /dev/null
    
    for i in {1..120}; do
        curl -s "$backend_url/api/users" > /dev/null 2>&1 &
        if [ $((i % 30)) -eq 0 ]; then
            print_status "Recovery phase 1: $i/120 seconds (2% errors + 200ms latency)"
        fi
        sleep 1
    done
    wait
    
    # Complete recovery
    print_status "Phase 4: Complete recovery...")
    reset_chaos
    
    for i in {1..180}; do  # 3 minutes of clean traffic
        curl -s "$backend_url/api/users" > /dev/null 2>&1 &
        if [ $((i % 60)) -eq 0 ]; then
            print_status "Recovery phase 2: $i/180 seconds (normal operations)"
        fi
        sleep 1
    done
    wait
    
    print_success "Combined stress scenario complete. All alerts should resolve."
}

# Scenario 4: Circuit Breaker Testing
scenario_circuit_breaker() {
    print_section "SCENARIO 4: CIRCUIT BREAKER TESTING"
    
    local backend_url=$(get_backend_url)
    
    print_status "This scenario demonstrates:"
    echo "• Circuit breaker state transitions"
    echo "• Failure threshold detection"
    echo "• Half-open state testing"
    echo "• Automatic recovery behavior"
    
    echo ""
    read -p "Press Enter to start the circuit breaker scenario..."
    echo ""
    
    reset_chaos
    sleep 5
    
    # Phase 1: Build up failures to trigger circuit breaker
    print_status "Phase 1: Building up failures to trigger circuit breaker..."
    curl -s -X POST "$backend_url/api/chaos/errors/0.8" > /dev/null  # 80% error rate
    curl -s -X POST "$backend_url/api/chaos/enable" > /dev/null
    
    print_status "Generating rapid requests to trigger circuit breaker..."
    for i in {1..60}; do
        # Rapid fire requests to quickly accumulate failures
        for j in {1..10}; do
            curl -s "$backend_url/api/users" > /dev/null 2>&1 &
        done
        if [ $((i % 15)) -eq 0 ]; then
            print_status "Circuit breaker trigger: $i/60 seconds (80% error rate)"
        fi
        sleep 1
    done
    wait
    
    print_warning "Circuit breaker should be in OPEN state now"
    
    # Phase 2: Test open circuit behavior
    print_status "Phase 2: Testing open circuit behavior..."
    reset_chaos  # Fix the underlying issue
    
    print_status "Underlying issue fixed, but circuit breaker should remain OPEN"
    for i in {1..30}; do
        curl -s "$backend_url/api/users" > /dev/null 2>&1 &
        if [ $((i % 10)) -eq 0 ]; then
            print_status "Open circuit test: $i/30 seconds (requests should be fast-failed)"
        fi
        sleep 1
    done
    wait
    
    # Phase 3: Half-open state testing
    print_status "Phase 3: Waiting for half-open state transition..."
    print_status "Circuit breaker should transition to HALF-OPEN after timeout period"
    
    # Wait for half-open transition (circuit breaker timeout)
    sleep 30
    
    print_status "Testing half-open state behavior..."
    for i in {1..20}; do
        curl -s "$backend_url/api/users" > /dev/null 2>&1 &
        if [ $((i % 5)) -eq 0 ]; then
            print_status "Half-open test: $i/20 seconds (limited requests allowed)"
        fi
        sleep 1
    done
    wait
    
    # Phase 4: Recovery to closed state
    print_status "Phase 4: Recovery to closed state..."
    print_status "Continued successful requests should close the circuit breaker"
    
    for i in {1..60}; do
        curl -s "$backend_url/api/users" > /dev/null 2>&1 &
        if [ $((i % 15)) -eq 0 ]; then
            print_status "Recovery test: $i/60 seconds (circuit should close)"
        fi
        sleep 1
    done
    wait
    
    print_success "Circuit breaker scenario complete. Circuit should be CLOSED."
    print_status "Monitor circuit_breaker_state metric in Grafana to observe state transitions."
}

# Scenario 5: Error Budget Burn Rate
scenario_error_budget() {
    print_section "SCENARIO 5: ERROR BUDGET BURN RATE"
    
    local backend_url=$(get_backend_url)
    
    print_status "This scenario demonstrates:"
    echo "• Error budget consumption patterns"
    echo "• Burn rate calculation and alerting"
    echo "• SLO vs SLI relationship"
    echo "• Decision-making metrics for releases"
    
    echo ""
    read -p "Press Enter to start the error budget scenario..."
    echo ""
    
    reset_chaos
    sleep 5
    
    # Phase 1: Controlled error burn
    print_status "Phase 1: Controlled error budget consumption..."
    print_status "Injecting exactly 5% error rate to match SLO threshold"
    
    curl -s -X POST "$backend_url/api/chaos/errors/0.05" > /dev/null
    curl -s -X POST "$backend_url/api/chaos/enable" > /dev/null
    
    # Generate steady traffic for 5 minutes
    for i in {1..300}; do
        curl -s "$backend_url/api/users" > /dev/null 2>&1 &
        if [ $((i % 60)) -eq 0 ]; then
            print_status "Error budget burn: $i/300 seconds (5% error rate)"
            print_status "This consumes error budget at maximum sustainable rate"
        fi
        sleep 1
    done
    wait
    
    print_success "Phase 1 complete. Error budget should show steady consumption."
    
    # Phase 2: Accelerated burn
    print_status "Phase 2: Accelerated error budget burn..."
    print_status "Increasing to 10% error rate (2x SLO threshold)"
    
    curl -s -X POST "$backend_url/api/chaos/errors/0.10" > /dev/null
    
    for i in {1..180}; do  # 3 minutes of accelerated burn
        curl -s "$backend_url/api/users" > /dev/null 2>&1 &
        if [ $((i % 60)) -eq 0 ]; then
            print_status "Accelerated burn: $i/180 seconds (10% error rate)"
        fi
        sleep 1
    done
    wait
    
    print_warning "Error budget burn rate should be 2x normal rate"
    print_warning "ErrorBudgetBurnRate alert may fire if budget < 50%"
    
    # Phase 3: Recovery and budget preservation
    print_status "Phase 3: Recovery and budget preservation..."
    reset_chaos
    
    print_status "Generating clean traffic to preserve remaining error budget"
    for i in {1..240}; do  # 4 minutes of clean traffic
        curl -s "$backend_url/api/users" > /dev/null 2>&1 &
        if [ $((i % 60)) -eq 0 ]; then
            print_status "Budget preservation: $i/240 seconds (0% error rate)"
        fi
        sleep 1
    done
    wait
    
    print_success "Error budget scenario complete."
    print_status "Check error_budget_remaining_percentage metric in Grafana"
    print_status "This data supports release vs reliability decisions"
}

# Function to show menu
show_menu() {
    print_section "CHAOS ENGINEERING SCENARIOS"
    echo "Select a scenario to run:"
    echo ""
    echo "1) Error Rate Testing"
    echo "2) Latency Testing" 
    echo "3) Combined Stress Test"
    echo "4) Circuit Breaker Testing"
    echo "5) Error Budget Burn Rate"
    echo "6) Reset Chaos State"
    echo "7) Run All Scenarios (Full Suite)"
    echo "8) Exit"
    echo ""
}

# Function to run all scenarios
run_all_scenarios() {
    print_section "RUNNING COMPLETE CHAOS ENGINEERING SUITE"
    
    print_warning "This will run all scenarios sequentially."
    print_warning "Total estimated time: 45-60 minutes"
    echo ""
    read -p "Press Enter to continue or Ctrl+C to cancel..."
    echo ""
    
    scenario_error_rate
    echo ""
    read -p "Press Enter to continue to latency testing..."
    echo ""
    
    scenario_latency
    echo ""
    read -p "Press Enter to continue to combined stress test..."
    echo ""
    
    scenario_combined_stress
    echo ""
    read -p "Press Enter to continue to circuit breaker testing..."
    echo ""
    
    scenario_circuit_breaker
    echo ""
    read -p "Press Enter to continue to error budget testing..."
    echo ""
    
    scenario_error_budget
    
    print_section "ALL SCENARIOS COMPLETE"
    print_success "Comprehensive chaos engineering testing completed!"
}

# Main function
main() {
    # Pre-flight check
    check_service
    
    while true; do
        show_menu
        read -p "Enter your choice (1-8): " choice
        echo ""
        
        case $choice in
            1)
                scenario_error_rate
                ;;
            2)
                scenario_latency
                ;;
            3)
                scenario_combined_stress
                ;;
            4)
                scenario_circuit_breaker
                ;;
            5)
                scenario_error_budget
                ;;
            6)
                reset_chaos
                ;;
            7)
                run_all_scenarios
                ;;
            8)
                print_status "Exiting chaos engineering scenarios."
                reset_chaos
                exit 0
                ;;
            *)
                print_error "Invalid choice. Please select 1-8."
                ;;
        esac
        
        echo ""
        read -p "Press Enter to return to main menu..."
        echo ""
    done
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi