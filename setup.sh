#!/bin/bash

set -e

echo "🚀 Starting Ironclad SRE Demo Setup..."

# Check tools
echo "📋 Checking required tools..."
command -v docker >/dev/null 2>&1 || { echo "❌ docker is required"; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo "❌ kubectl is required"; exit 1; }
command -v minikube >/dev/null 2>&1 || { echo "❌ minikube is required"; exit 1; }
echo "✅ All tools present"

# Start minikube
echo "🔧 Starting Minikube..."
minikube start --cpus=4 --memory=8192 --driver=docker
minikube addons enable metrics-server

# Build images
echo "🏗️ Building Docker images..."
eval $(minikube docker-env)
cd backend && npm install && cd ..
docker build -t ironclad-backend:latest ./backend

# Deploy
echo "🚀 Deploying to Kubernetes..."
kubectl apply -f k8s/base/
kubectl apply -f k8s/monitoring/

# Wait for ready
echo "⏳ Waiting for pods to be ready..."
kubectl wait --for=condition=ready pod -l app=postgres -n ironclad-demo --timeout=120s
kubectl wait --for=condition=ready pod -l app=backend -n ironclad-demo --timeout=120s
kubectl wait --for=condition=ready pod -l app=prometheus -n ironclad-demo --timeout=120s
kubectl wait --for=condition=ready pod -l app=grafana -n ironclad-demo --timeout=120s

# Get URLs
echo "✅ Deployment complete!"
echo ""
echo "📊 Service URLs:"
echo "Backend: $(minikube service backend -n ironclad-demo --url | head -1)"
echo "Prometheus: $(minikube service prometheus -n ironclad-demo --url)"
echo "Grafana: $(minikube service grafana -n ironclad-demo --url) (admin/admin)"
echo ""
echo "🎯 Run './demo.sh' to see the demo"