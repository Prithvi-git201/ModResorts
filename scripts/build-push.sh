#!/bin/bash

# Build and Push Script for ModResorts Application
# This script builds the Docker image and pushes it to a container registry

set -e
set -o pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=========================================="
echo "ModResorts - Docker Build and Push Script"
echo "=========================================="
echo ""

# Project configuration
PROJECT_NAME="modresorts"

# Sanitize image name: lowercase, replace non-alphanumeric with hyphens, trim hyphens
IMAGE_NAME=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-*//;s/-*$//')

echo -e "${GREEN}Project:${NC} $PROJECT_NAME"
echo -e "${GREEN}Sanitized Image Name:${NC} $IMAGE_NAME"
echo ""

# Prompt for registry type
echo "Select container registry:"
echo "1. AWS ECR (Elastic Container Registry)"
echo "2. Docker Hub"
read -p "Enter choice (1 or 2): " REGISTRY_CHOICE

if [ "$REGISTRY_CHOICE" == "1" ]; then
    echo ""
    echo -e "${YELLOW}=== AWS ECR Configuration ===${NC}"
    
    # Prompt for AWS region
    read -p "Enter AWS region (e.g., us-east-1): " AWS_REGION
    
    # Prompt for ECR repository name
    read -p "Enter ECR repository name [$IMAGE_NAME]: " ECR_REPO
    ECR_REPO=${ECR_REPO:-$IMAGE_NAME}
    
    # Get AWS account ID
    echo -e "${YELLOW}Getting AWS account ID...${NC}"
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    
    if [ -z "$ACCOUNT_ID" ]; then
        echo -e "${RED}Error: Failed to get AWS account ID. Please check AWS CLI configuration.${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}AWS Account ID:${NC} $ACCOUNT_ID"
    
    # Construct registry URL
    REGISTRY_URL="$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"
    
    # Authenticate with ECR
    echo -e "${YELLOW}Authenticating with AWS ECR...${NC}"
    aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$REGISTRY_URL"
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: ECR authentication failed${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}Successfully authenticated with ECR${NC}"
    
    # Check if repository exists, create if it doesn't
    echo -e "${YELLOW}Checking if ECR repository exists...${NC}"
    aws ecr describe-repositories --repository-names "$ECR_REPO" --region "$AWS_REGION" >/dev/null 2>&1 || {
        echo -e "${YELLOW}Repository does not exist. Creating ECR repository...${NC}"
        aws ecr create-repository --repository-name "$ECR_REPO" --region "$AWS_REGION"
        echo -e "${GREEN}ECR repository created successfully${NC}"
    }
    
    # Prompt for image tag
    read -p "Enter image tag [latest]: " IMAGE_TAG
    IMAGE_TAG=${IMAGE_TAG:-latest}
    
    # Sanitize tag
    IMAGE_TAG=$(echo "$IMAGE_TAG" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9.-' '-' | sed 's/^-*//;s/-*$//')
    
    FULL_IMAGE_NAME="$REGISTRY_URL/$ECR_REPO:$IMAGE_TAG"
    
elif [ "$REGISTRY_CHOICE" == "2" ]; then
    echo ""
    echo -e "${YELLOW}=== Docker Hub Configuration ===${NC}"
    
    # Prompt for Docker Hub credentials
    read -p "Enter Docker Hub username: " DOCKER_USERNAME
    read -sp "Enter Docker Hub password or access token: " DOCKER_PASSWORD
    echo ""
    
    # Authenticate with Docker Hub
    echo -e "${YELLOW}Authenticating with Docker Hub...${NC}"
    echo "$DOCKER_PASSWORD" | docker login --username "$DOCKER_USERNAME" --password-stdin
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: Docker Hub authentication failed${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}Successfully authenticated with Docker Hub${NC}"
    
    # Prompt for image tag
    read -p "Enter image tag [latest]: " IMAGE_TAG
    IMAGE_TAG=${IMAGE_TAG:-latest}
    
    # Sanitize tag
    IMAGE_TAG=$(echo "$IMAGE_TAG" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9.-' '-' | sed 's/^-*//;s/-*$//')
    
    FULL_IMAGE_NAME="$DOCKER_USERNAME/$IMAGE_NAME:$IMAGE_TAG"
    
else
    echo -e "${RED}Invalid choice. Exiting.${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}Full image name:${NC} $FULL_IMAGE_NAME"
echo ""

# Build Docker image
echo -e "${YELLOW}Building Docker image...${NC}"
docker build -t "$FULL_IMAGE_NAME" .

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Docker build failed${NC}"
    exit 1
fi

echo -e "${GREEN}Docker image built successfully${NC}"
echo ""

# Push Docker image
echo -e "${YELLOW}Pushing Docker image to registry...${NC}"
docker push "$FULL_IMAGE_NAME"

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Docker push failed${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}=========================================="
echo -e "Docker image pushed successfully!"
echo -e "==========================================${NC}"
echo ""
echo -e "${GREEN}Image:${NC} $FULL_IMAGE_NAME"
echo ""
echo "Next steps:"
echo "1. Update ECS task definition with the image URI"
echo "2. Run the deploy-image.sh script to deploy to ECS"
echo ""
