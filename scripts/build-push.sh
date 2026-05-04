#!/bin/bash

# ============================================
# Build and Push Script for ModResorts Application
# Platform: Linux/macOS
# Target: AWS ECR or Docker Hub
# ============================================

set -e  # Exit on error
set -o pipefail  # Exit on pipe failure

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}ModResorts - Build and Push Docker Image${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""

# Project configuration
PROJECT_NAME="modresorts"

# Sanitize project name for Docker (lowercase, hyphenate)
IMAGE_NAME=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-*//;s/-*$//')

echo -e "${YELLOW}Project: ${IMAGE_NAME}${NC}"
echo ""

# Prompt for image tag
echo -e "${YELLOW}Enter image tag (default: latest):${NC}"
read -r IMAGE_TAG
IMAGE_TAG=${IMAGE_TAG:-latest}

# Sanitize tag (lowercase, hyphenate, trim)
IMAGE_TAG=$(echo "$IMAGE_TAG" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9.-' '-' | sed 's/^-*//;s/-*$//')
IMAGE_TAG=${IMAGE_TAG:-latest}

echo -e "${GREEN}Using tag: ${IMAGE_TAG}${NC}"
echo ""

# Select registry type
echo -e "${YELLOW}Select container registry:${NC}"
echo "1. AWS ECR (Elastic Container Registry)"
echo "2. Docker Hub"
read -r -p "Enter choice (1 or 2): " REGISTRY_CHOICE

if [ "$REGISTRY_CHOICE" = "1" ]; then
    # AWS ECR Configuration
    echo ""
    echo -e "${GREEN}=== AWS ECR Configuration ===${NC}"
    
    read -r -p "Enter AWS Region (e.g., us-east-1): " AWS_REGION
    read -r -p "Enter AWS Account ID: " AWS_ACCOUNT_ID
    read -r -p "Enter ECR Repository Name (default: ${IMAGE_NAME}): " ECR_REPO
    ECR_REPO=${ECR_REPO:-$IMAGE_NAME}
    
    REGISTRY_URL="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
    FULL_IMAGE_NAME="${REGISTRY_URL}/${ECR_REPO}:${IMAGE_TAG}"
    
    echo ""
    echo -e "${GREEN}Authenticating with AWS ECR...${NC}"
    aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$REGISTRY_URL"
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}ECR authentication failed. Please check your AWS credentials.${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}ECR authentication successful!${NC}"
    
    # Check if repository exists, create if not
    echo -e "${GREEN}Checking ECR repository...${NC}"
    aws ecr describe-repositories --repository-names "$ECR_REPO" --region "$AWS_REGION" >/dev/null 2>&1 || {
        echo -e "${YELLOW}Repository does not exist. Creating...${NC}"
        aws ecr create-repository --repository-name "$ECR_REPO" --region "$AWS_REGION"
        echo -e "${GREEN}Repository created successfully!${NC}"
    }
    
elif [ "$REGISTRY_CHOICE" = "2" ]; then
    # Docker Hub Configuration
    echo ""
    echo -e "${GREEN}=== Docker Hub Configuration ===${NC}"
    
    read -r -p "Enter Docker Hub username: " DOCKER_USERNAME
    read -r -s -p "Enter Docker Hub password/token: " DOCKER_PASSWORD
    echo ""
    
    FULL_IMAGE_NAME="${DOCKER_USERNAME}/${IMAGE_NAME}:${IMAGE_TAG}"
    
    echo ""
    echo -e "${GREEN}Authenticating with Docker Hub...${NC}"
    echo "$DOCKER_PASSWORD" | docker login --username "$DOCKER_USERNAME" --password-stdin
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}Docker Hub authentication failed.${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}Docker Hub authentication successful!${NC}"
    
else
    echo -e "${RED}Invalid choice. Exiting.${NC}"
    exit 1
fi

# Build Docker image
echo ""
echo -e "${GREEN}Building Docker image: ${FULL_IMAGE_NAME}${NC}"
echo -e "${YELLOW}This may take several minutes...${NC}"
echo ""

docker build -t "$FULL_IMAGE_NAME" .

if [ $? -ne 0 ]; then
    echo -e "${RED}Docker build failed!${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}Docker image built successfully!${NC}"

# Push Docker image
echo ""
echo -e "${GREEN}Pushing image to registry: ${FULL_IMAGE_NAME}${NC}"
echo ""

docker push "$FULL_IMAGE_NAME"

if [ $? -ne 0 ]; then
    echo -e "${RED}Docker push failed!${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}Image pushed successfully!${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo -e "${YELLOW}Image: ${FULL_IMAGE_NAME}${NC}"
echo ""
echo -e "${GREEN}Next steps:${NC}"
echo "1. Update ECS task definition with this image URI"
echo "2. Run deploy-image.sh to deploy to AWS ECS"
echo ""
