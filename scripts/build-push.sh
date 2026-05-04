#!/bin/bash

# Build and Push Docker Image Script for ModResorts Backend
# This script builds the Docker image and pushes it to a container registry

set -e

echo "=========================================="
echo "ModResorts Backend - Build and Push Script"
echo "=========================================="
echo ""

# Project configuration
PROJECT_NAME="modresorts-backend"

# Sanitize image name: lowercase, hyphenate spaces/special chars, trim hyphens
IMAGE_NAME=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-*//;s/-*$//')

echo "Project: $PROJECT_NAME"
echo "Sanitized Image Name: $IMAGE_NAME"
echo ""

# Prompt for registry type
echo "Select Container Registry:"
echo "1. AWS ECR (Elastic Container Registry)"
echo "2. Docker Hub"
read -p "Enter your choice (1 or 2): " REGISTRY_CHOICE

if [ "$REGISTRY_CHOICE" == "1" ]; then
    echo ""
    echo "=== AWS ECR Configuration ==="
    
    # Prompt for AWS region
    read -p "Enter AWS Region (e.g., us-east-1): " AWS_REGION
    
    # Prompt for AWS Account ID
    read -p "Enter AWS Account ID: " AWS_ACCOUNT_ID
    
    # Prompt for ECR repository name
    read -p "Enter ECR Repository Name [$IMAGE_NAME]: " ECR_REPO
    ECR_REPO=${ECR_REPO:-$IMAGE_NAME}
    
    # Construct registry URL
    REGISTRY_URL="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"
    
    echo ""
    echo "Authenticating with AWS ECR..."
    aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$REGISTRY_URL"
    
    if [ $? -ne 0 ]; then
        echo "ERROR: ECR authentication failed"
        exit 1
    fi
    
    echo "ECR authentication successful"
    
    # Check if repository exists, create if not
    echo "Checking if ECR repository exists..."
    aws ecr describe-repositories --repository-names "$ECR_REPO" --region "$AWS_REGION" >/dev/null 2>&1 || {
        echo "Repository does not exist. Creating ECR repository: $ECR_REPO"
        aws ecr create-repository --repository-name "$ECR_REPO" --region "$AWS_REGION"
        echo "ECR repository created successfully"
    }
    
    # Prompt for image tag
    read -p "Enter image tag [latest]: " IMAGE_TAG
    IMAGE_TAG=${IMAGE_TAG:-latest}
    
    # Sanitize tag
    IMAGE_TAG=$(echo "$IMAGE_TAG" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9.-' '-' | sed 's/^-*//;s/-*$//')
    
    FULL_IMAGE_NAME="$REGISTRY_URL/$ECR_REPO:$IMAGE_TAG"
    
elif [ "$REGISTRY_CHOICE" == "2" ]; then
    echo ""
    echo "=== Docker Hub Configuration ==="
    
    # Prompt for Docker Hub username
    read -p "Enter Docker Hub Username: " DOCKER_USERNAME
    
    # Prompt for Docker Hub password
    read -sp "Enter Docker Hub Password: " DOCKER_PASSWORD
    echo ""
    
    echo "Authenticating with Docker Hub..."
    echo "$DOCKER_PASSWORD" | docker login --username "$DOCKER_USERNAME" --password-stdin
    
    if [ $? -ne 0 ]; then
        echo "ERROR: Docker Hub authentication failed"
        exit 1
    fi
    
    echo "Docker Hub authentication successful"
    
    # Prompt for image tag
    read -p "Enter image tag [latest]: " IMAGE_TAG
    IMAGE_TAG=${IMAGE_TAG:-latest}
    
    # Sanitize tag
    IMAGE_TAG=$(echo "$IMAGE_TAG" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9.-' '-' | sed 's/^-*//;s/-*$//')
    
    FULL_IMAGE_NAME="$DOCKER_USERNAME/$IMAGE_NAME:$IMAGE_TAG"
    
else
    echo "ERROR: Invalid choice. Please select 1 or 2."
    exit 1
fi

echo ""
echo "=========================================="
echo "Building Docker Image"
echo "=========================================="
echo "Image: $FULL_IMAGE_NAME"
echo ""

# Build the Docker image
docker build -t "$FULL_IMAGE_NAME" .

if [ $? -ne 0 ]; then
    echo "ERROR: Docker build failed"
    exit 1
fi

echo ""
echo "Docker build completed successfully"

echo ""
echo "=========================================="
echo "Pushing Docker Image"
echo "=========================================="
echo "Pushing: $FULL_IMAGE_NAME"
echo ""

# Push the Docker image
docker push "$FULL_IMAGE_NAME"

if [ $? -ne 0 ]; then
    echo "ERROR: Docker push failed"
    exit 1
fi

echo ""
echo "=========================================="
echo "Build and Push Completed Successfully"
echo "=========================================="
echo "Image: $FULL_IMAGE_NAME"
echo ""
echo "You can now deploy this image to AWS ECS using the deploy-image.sh script"
echo ""
