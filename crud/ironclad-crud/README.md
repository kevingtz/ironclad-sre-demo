# Ironclad CRUD Demo

Simple CRUD application for user management.

## Requirements
- Docker
- Kubernetes (Minikube) or Docker Compose

## Quick Start with Docker Compose
```bash
docker-compose up
```
Open http://localhost in your browser

## Quick Start with Kubernetes
```bash
# Start Minikube
minikube start

# Build images
eval $(minikube docker-env)
docker build -t ironclad-backend:latest ./backend
docker build -t ironclad-frontend:latest ./frontend

# Deploy
kubectl apply -f k8s/

# Get URLs
minikube service frontend --url
```

## Features
- Create, Read, Update, Delete users
- Input validation for:
  - Names (letters, spaces, hyphens only)
  - Email (valid format)
  - Phone (US format)
  - Date of birth (MM/DD/YYYY)
- PostgreSQL database
- Simple web interface