#!/bin/bash

# ============================================
# AWS ECS Fargate Deployment Script for ModResorts
# Platform: Linux/macOS
# ============================================

set -e  # Exit on error
set -o pipefail  # Exit on pipe failure

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}ModResorts - AWS ECS Fargate Deployment${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""

# Configuration
PROJECT_NAME="modresorts"
TASK_FAMILY="modresorts-task"
SERVICE_NAME="modresorts-service"

# Prompt for AWS configuration
echo -e "${YELLOW}=== AWS Configuration ===${NC}"
read -r -p "Enter AWS Region (e.g., us-east-1): " AWS_REGION
read -r -p "Enter ECS Cluster Name: " CLUSTER_NAME

# Get AWS Account ID
echo -e "${GREEN}Retrieving AWS Account ID...${NC}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo -e "${GREEN}Account ID: ${ACCOUNT_ID}${NC}"
echo ""

# Check/Create ECS Cluster
echo -e "${GREEN}Checking ECS cluster...${NC}"
aws ecs describe-clusters --clusters "$CLUSTER_NAME" --region "$AWS_REGION" >/dev/null 2>&1 || {
    echo -e "${YELLOW}Cluster does not exist. Creating...${NC}"
    aws ecs create-cluster --cluster-name "$CLUSTER_NAME" --region "$AWS_REGION"
    echo -e "${GREEN}Cluster created successfully!${NC}"
}
echo ""

# Prompt for network configuration
echo -e "${YELLOW}=== Network Configuration ===${NC}"
read -r -p "Enter VPC ID: " VPC_ID
read -r -p "Enter Subnet IDs (comma-separated, at least 2): " SUBNETS_INPUT
read -r -p "Enter Security Group ID: " SECURITY_GROUP

# Parse subnets
IFS=',' read -ra SUBNETS <<< "$SUBNETS_INPUT"
SUBNET_1=$(echo "${SUBNETS[0]}" | xargs)
SUBNET_2=$(echo "${SUBNETS[1]}" | xargs)

echo ""

# Prompt for image URI
echo -e "${YELLOW}=== Container Image ===${NC}"
read -r -p "Enter ECR Image URI (e.g., 123456789.dkr.ecr.us-east-1.amazonaws.com/modresorts:latest): " IMAGE_URI
echo ""

# Prompt for database configuration
echo -e "${YELLOW}=== Database Configuration ===${NC}"
read -r -p "Enter Database URL (default: jdbc:h2:mem:testdb): " DB_URL
DB_URL=${DB_URL:-jdbc:h2:mem:testdb}
read -r -p "Enter Database Username (default: sa): " DB_USERNAME
DB_USERNAME=${DB_USERNAME:-sa}
read -r -s -p "Enter Database Password (default: empty): " DB_PASSWORD
echo ""
read -r -p "Enter Database Driver (default: org.h2.Driver): " DB_DRIVER
DB_DRIVER=${DB_DRIVER:-org.h2.Driver}
echo ""

# Prompt for Redis configuration
echo -e "${YELLOW}=== Redis Configuration ===${NC}"
read -r -p "Enter Redis Host (default: localhost): " REDIS_HOST
REDIS_HOST=${REDIS_HOST:-localhost}
read -r -p "Enter Redis Port (default: 6379): " REDIS_PORT
REDIS_PORT=${REDIS_PORT:-6379}
read -r -s -p "Enter Redis Password (default: empty): " REDIS_PASSWORD
echo ""
echo ""

# Load balancer configuration
echo -e "${YELLOW}=== Load Balancer Configuration ===${NC}"
read -r -p "Do you need a load balancer for this service? (y/n): " NEED_LB

if [[ "$NEED_LB" =~ ^[Yy]$ ]]; then
    echo -e "${GREEN}Creating Application Load Balancer and Target Group...${NC}"
    
    # Create ALB
    ALB_NAME="${PROJECT_NAME}-alb"
    echo -e "${YELLOW}Creating ALB: ${ALB_NAME}${NC}"
    ALB_ARN=$(aws elbv2 create-load-balancer \
        --name "$ALB_NAME" \
        --subnets "$SUBNET_1" "$SUBNET_2" \
        --security-groups "$SECURITY_GROUP" \
        --scheme internet-facing \
        --type application \
        --ip-address-type ipv4 \
        --region "$AWS_REGION" \
        --query 'LoadBalancers[0].LoadBalancerArn' \
        --output text)
    
    echo -e "${GREEN}ALB created: ${ALB_ARN}${NC}"
    
    # Get ALB DNS name
    ALB_DNS=$(aws elbv2 describe-load-balancers \
        --load-balancer-arns "$ALB_ARN" \
        --region "$AWS_REGION" \
        --query 'LoadBalancers[0].DNSName' \
        --output text)
    
    # Create Target Group with target-type ip (required for Fargate)
    TG_NAME="${PROJECT_NAME}-tg"
    echo -e "${YELLOW}Creating Target Group: ${TG_NAME}${NC}"
    TARGET_GROUP_ARN=$(aws elbv2 create-target-group \
        --name "$TG_NAME" \
        --protocol HTTP \
        --port 8080 \
        --vpc-id "$VPC_ID" \
        --target-type ip \
        --health-check-enabled \
        --health-check-protocol HTTP \
        --health-check-path "/actuator/health" \
        --health-check-interval-seconds 30 \
        --health-check-timeout-seconds 5 \
        --healthy-threshold-count 2 \
        --unhealthy-threshold-count 3 \
        --region "$AWS_REGION" \
        --query 'TargetGroups[0].TargetGroupArn' \
        --output text)
    
    echo -e "${GREEN}Target Group created: ${TARGET_GROUP_ARN}${NC}"
    
    # Create Listener
    echo -e "${YELLOW}Creating ALB Listener...${NC}"
    aws elbv2 create-listener \
        --load-balancer-arn "$ALB_ARN" \
        --protocol HTTP \
        --port 80 \
        --default-actions Type=forward,TargetGroupArn="$TARGET_GROUP_ARN" \
        --region "$AWS_REGION" >/dev/null
    
    echo -e "${GREEN}Listener created successfully!${NC}"
    echo ""
else
    echo -e "${YELLOW}Skipping load balancer creation.${NC}"
    TARGET_GROUP_ARN=""
    echo ""
fi

# Create CloudWatch Log Group
echo -e "${GREEN}Creating CloudWatch Log Group...${NC}"
aws logs create-log-group --log-group-name "/ecs/${PROJECT_NAME}" --region "$AWS_REGION" 2>/dev/null || echo -e "${YELLOW}Log group already exists.${NC}"
echo ""

# Replace placeholders in task definition
echo -e "${GREEN}Preparing task definition...${NC}"
TASK_DEF_FILE="ecs/task-definition.json"
TASK_DEF_TEMP="ecs/task-definition-temp.json"

cp "$TASK_DEF_FILE" "$TASK_DEF_TEMP"

sed -i "s|{{IMAGE_URI}}|${IMAGE_URI}|g" "$TASK_DEF_TEMP"
sed -i "s|{{AWS_REGION}}|${AWS_REGION}|g" "$TASK_DEF_TEMP"
sed -i "s|{{ACCOUNT_ID}}|${ACCOUNT_ID}|g" "$TASK_DEF_TEMP"
sed -i "s|{{DB_URL}}|${DB_URL}|g" "$TASK_DEF_TEMP"
sed -i "s|{{DB_USERNAME}}|${DB_USERNAME}|g" "$TASK_DEF_TEMP"
sed -i "s|{{DB_PASSWORD}}|${DB_PASSWORD}|g" "$TASK_DEF_TEMP"
sed -i "s|{{DB_DRIVER}}|${DB_DRIVER}|g" "$TASK_DEF_TEMP"
sed -i "s|{{REDIS_HOST}}|${REDIS_HOST}|g" "$TASK_DEF_TEMP"
sed -i "s|{{REDIS_PORT}}|${REDIS_PORT}|g" "$TASK_DEF_TEMP"
sed -i "s|{{REDIS_PASSWORD}}|${REDIS_PASSWORD}|g" "$TASK_DEF_TEMP"

# Register task definition
echo -e "${GREEN}Registering task definition...${NC}"
TASK_DEF_ARN=$(aws ecs register-task-definition \
    --cli-input-json file://"$TASK_DEF_TEMP" \
    --region "$AWS_REGION" \
    --query 'taskDefinition.taskDefinitionArn' \
    --output text)

echo -e "${GREEN}Task definition registered: ${TASK_DEF_ARN}${NC}"
rm "$TASK_DEF_TEMP"
echo ""

# Prepare service definition
echo -e "${GREEN}Preparing service definition...${NC}"
SERVICE_DEF_FILE="ecs/service-definition.json"
SERVICE_DEF_TEMP="ecs/service-definition-temp.json"

cp "$SERVICE_DEF_FILE" "$SERVICE_DEF_TEMP"

sed -i "s|{{CLUSTER_NAME}}|${CLUSTER_NAME}|g" "$SERVICE_DEF_TEMP"
sed -i "s|{{SUBNET_1}}|${SUBNET_1}|g" "$SERVICE_DEF_TEMP"
sed -i "s|{{SUBNET_2}}|${SUBNET_2}|g" "$SERVICE_DEF_TEMP"
sed -i "s|{{SECURITY_GROUP}}|${SECURITY_GROUP}|g" "$SERVICE_DEF_TEMP"

if [[ "$NEED_LB" =~ ^[Yy]$ ]]; then
    sed -i "s|{{TARGET_GROUP_ARN}}|${TARGET_GROUP_ARN}|g" "$SERVICE_DEF_TEMP"
else
    # Remove loadBalancers section if no LB needed
    python3 -c "
import json
with open('$SERVICE_DEF_TEMP', 'r') as f:
    data = json.load(f)
data.pop('loadBalancers', None)
data.pop('healthCheckGracePeriodSeconds', None)
with open('$SERVICE_DEF_TEMP', 'w') as f:
    json.dump(data, f, indent=2)
" 2>/dev/null || {
    # Fallback if python3 not available
    echo -e "${YELLOW}Warning: Could not remove loadBalancers section. Manual cleanup may be needed.${NC}"
}
fi

# Check if service exists
echo -e "${GREEN}Checking if service exists...${NC}"
SERVICE_EXISTS=$(aws ecs describe-services \
    --cluster "$CLUSTER_NAME" \
    --services "$SERVICE_NAME" \
    --region "$AWS_REGION" \
    --query 'services[?status==`ACTIVE`].serviceName' \
    --output text 2>/dev/null || echo "")

if [ -z "$SERVICE_EXISTS" ]; then
    # Create new service
    echo -e "${GREEN}Creating new ECS service...${NC}"
    aws ecs create-service \
        --cli-input-json file://"$SERVICE_DEF_TEMP" \
        --region "$AWS_REGION" >/dev/null
    
    echo -e "${GREEN}Service created successfully!${NC}"
else
    # Update existing service
    echo -e "${YELLOW}Service already exists. Updating...${NC}"
    aws ecs update-service \
        --cluster "$CLUSTER_NAME" \
        --service "$SERVICE_NAME" \
        --task-definition "$TASK_DEF_ARN" \
        --desired-count 2 \
        --region "$AWS_REGION" >/dev/null
    
    echo -e "${GREEN}Service updated successfully!${NC}"
fi

rm "$SERVICE_DEF_TEMP"
echo ""

# Wait for service stability
echo -e "${GREEN}Waiting for service to become stable...${NC}"
echo -e "${YELLOW}This may take several minutes...${NC}"
aws ecs wait services-stable \
    --cluster "$CLUSTER_NAME" \
    --services "$SERVICE_NAME" \
    --region "$AWS_REGION"

echo -e "${GREEN}Service is stable!${NC}"
echo ""

# Display deployment information
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}Deployment Successful!${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo -e "${YELLOW}Cluster:${NC} $CLUSTER_NAME"
echo -e "${YELLOW}Service:${NC} $SERVICE_NAME"
echo -e "${YELLOW}Task Definition:${NC} $TASK_DEF_ARN"
echo -e "${YELLOW}Region:${NC} $AWS_REGION"

if [[ "$NEED_LB" =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Load Balancer DNS:${NC} http://${ALB_DNS}"
    echo ""
    echo -e "${GREEN}Access your application at:${NC} http://${ALB_DNS}"
fi

echo ""
echo -e "${YELLOW}CloudWatch Logs:${NC} /ecs/${PROJECT_NAME}"
echo ""
echo -e "${GREEN}Verify deployment:${NC}"
echo "aws ecs describe-services --cluster $CLUSTER_NAME --services $SERVICE_NAME --region $AWS_REGION"
echo ""
echo -e "${GREEN}View logs:${NC}"
echo "aws logs tail /ecs/${PROJECT_NAME} --follow --region $AWS_REGION"
echo ""
