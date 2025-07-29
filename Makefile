.PHONY: help build deploy clean test demo

# Variables
DOCKER_REGISTRY ?= local
BACKEND_IMAGE = $(DOCKER_REGISTRY)/ironclad-backend:latest
NAMESPACE = ironclad-demo

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

check-tools: ## Check required tools
	@echo "Checking required tools..."
	@command -v docker >/dev/null 2>&1 || { echo "docker is required but not installed."; exit 1; }
	@command -v kubectl >/dev/null 2>&1 || { echo "kubectl is required but not installed."; exit 1; }
	@command -v minikube >/dev/null 2>&1 || { echo "minikube is required but not installed."; exit 1; }
	@echo "All required tools are installed ✓"

start-minikube: ## Start minikube
	@echo "Starting minikube..."
	minikube start --cpus=4 --memory=8192 --driver=docker
	minikube addons enable metrics-server
	@echo "Minikube started ✓"

build-backend: ## Build backend Docker image
	@echo "Building backend image..."
	cd backend && npm install
	eval $$(minikube docker-env) && docker build -t ironclad-backend:latest ./backend
	@echo "Backend image built ✓"

build: build-backend ## Build all images

deploy-namespace: ## Deploy namespace
	kubectl apply -f k8s/base/namespace.yaml

deploy-secrets: deploy-namespace ## Deploy secrets
	kubectl apply -f k8s/base/secrets.yaml

deploy-postgres: deploy-secrets ## Deploy PostgreSQL
	kubectl apply -f k8s/base/postgres.yaml
	@echo "Waiting for PostgreSQL to be ready..."
	kubectl wait --for=condition=ready pod -l app=postgres -n $(NAMESPACE) --timeout=120s

deploy-backend: deploy-postgres ## Deploy backend
	kubectl apply -f k8s/base/backend.yaml
	@echo "Waiting for backend to be ready..."
	kubectl wait --for=condition=ready pod -l app=backend -n $(NAMESPACE) --timeout=120s

deploy-monitoring: ## Deploy monitoring stack
	kubectl apply -f k8s/monitoring/prometheus.yaml
	kubectl apply -f k8s/monitoring/grafana.yaml
	@echo "Waiting for monitoring stack to be ready..."
	kubectl wait --for=condition=ready pod -l app=prometheus -n $(NAMESPACE) --timeout=120s
	kubectl wait --for=condition=ready pod -l app=grafana -n $(NAMESPACE) --timeout=120s

deploy: deploy-backend deploy-monitoring ## Deploy everything
	@echo "Deployment complete! ✓"
	@echo ""
	@echo "Getting service URLs..."
	@$(MAKE) get-urls

get-urls: ## Get service URLs
	@echo "Service URLs:"
	@echo "Backend: http://$$(minikube service backend -n $(NAMESPACE) --url | head -1)"
	@echo "Prometheus: http://$$(minikube service prometheus -n $(NAMESPACE) --url)"
	@echo "Grafana: http://$$(minikube service grafana -n $(NAMESPACE) --url)"
	@echo ""
	@echo "Grafana login: admin/admin"

test-endpoint: ## Test the API endpoint
	@echo "Testing API endpoint..."
	@BACKEND_URL=$$(minikube service backend -n $(NAMESPACE) --url | head -1) && \
	curl -s $$BACKEND_URL/health | jq '.' || echo "Backend not ready yet"

demo: ## Run demo script
	@echo "Running demo..."
	@./demo.sh

chaos-enable: ## Enable chaos engineering
	@BACKEND_URL=$$(minikube service backend -n $(NAMESPACE) --url | head -1) && \
	curl -X POST $$BACKEND_URL/api/chaos/enable

chaos-latency: ## Add 500ms latency
	@BACKEND_URL=$$(minikube service backend -n $(NAMESPACE) --url | head -1) && \
	curl -X POST $$BACKEND_URL/api/chaos/latency/500

chaos-errors: ## Add 10% error rate
	@BACKEND_URL=$$(minikube service backend -n $(NAMESPACE) --url | head -1) && \
	curl -X POST $$BACKEND_URL/api/chaos/errors/0.1

logs-backend: ## Show backend logs
	kubectl logs -f deployment/backend -n $(NAMESPACE)

logs-prometheus: ## Show Prometheus logs
	kubectl logs -f deployment/prometheus -n $(NAMESPACE)

port-forward-grafana: ## Port forward Grafana
	kubectl port-forward -n $(NAMESPACE) svc/grafana 3000:3000

clean: ## Clean up everything
	kubectl delete namespace $(NAMESPACE) --ignore-not-found=true
	minikube stop
	@echo "Cleanup complete ✓"

all: check-tools start-minikube build deploy ## Full setup from scratch