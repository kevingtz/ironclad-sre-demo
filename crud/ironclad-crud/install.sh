#!/bin/bash

echo "Installing dependencies..."
cd backend && npm install && cd ..

echo "Choose deployment method:"
echo "1) Docker Compose"
echo "2) Kubernetes (Minikube)"
read -p "Enter choice (1 or 2): " choice

if [ "$choice" = "1" ]; then
    echo "Starting with Docker Compose..."
    docker-compose up -d
    echo "Application running at http://localhost"
elif [ "$choice" = "2" ]; then
    echo "Starting Minikube..."
    minikube start
    
    echo "Building images..."
    eval $(minikube docker-env)
    docker build -t ironclad-backend:latest ./backend
    docker build -t ironclad-frontend:latest ./frontend
    
    echo "Deploying to Kubernetes..."
    kubectl apply -f k8s/
    
    echo "Waiting for pods to be ready..."
    kubectl wait --for=condition=ready pod -l app=backend --timeout=60s
    
    echo "Getting URLs..."
    echo "Frontend: $(minikube service frontend --url)"
    echo "Backend: $(minikube service backend --url)"
else
    echo "Invalid choice"
fi