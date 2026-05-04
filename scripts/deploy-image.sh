#!/bin/bash

# Deploy Script for ModResorts Application to AWS ECS Fargate
# This script deploys the Docker image to AWS ECS Fargate

set -e
set -o pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "=========================================="
echo "ModResorts - AWS ECS Fargate Deployment"
echo "=========================================="
echo ""

# Project configuration
PROJECT_NAME="modresorts"
TASK_FAMILY="modresorts-task"
SERVICE_NAME="modresorts-service"

# Prompt for AWS configuration
echo -e "${YELLOW}=== AWS Configuration ===${NC}"
read -p "Enter AWS region (e.g., us-east-1): " AWS_REGION
read -p "Enter ECS cluster name: " CLUSTER_NAME
echo ""

# Get AWS Account ID
echo -e "${YELLOW}Getting AWS account ID...${NC}"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

if [ -z "$ACCOUNT_ID" ]; then
    echo -e "${RED}Error: Failed to get AWS account ID. Please check AWS CLI configuration.${NC}"
    exit 1
fi

echo -e "${GREEN}AWS Account ID:${NC} $ACCOUNT_ID"
echo ""

# Check if cluster exists, create if it doesn't
echo -e "${YELLOW}Checking if ECS cluster exists...${NC}"
aws ecs describe-clusters --clusters "$CLUSTER_NAME" --region "$AWS_REGION" >/dev/null 2>&1 || {
    echo -e "${YELLOW}Cluster does not exist. Creating ECS cluster...${NC}"
    aws ecs create-cluster --cluster-name "$CLUSTER_NAME" --region "$AWS_REGION"
    echo -e "${GREEN}ECS cluster created successfully${NC}"
}
echo ""

# Prompt for network configuration
echo -e "${YELLOW}=== Network Configuration ===${NC}"
read -p "Enter VPC ID: " VPC_ID
read -p "Enter Subnet IDs (comma-separated, at least 2): " SUBNETS_INPUT
read -p "Enter Security Group ID: " SECURITY_GROUP

# Parse subnets
IFS=',' read -ra SUBNET_ARRAY <<< "$SUBNETS_INPUT"
SUBNET_1=$(echo "${SUBNET_ARRAY[0]}" | xargs)
SUBNET_2=$(echo "${SUBNET_ARRAY[1]}" | xargs)

echo ""

# Prompt for image URI
echo -e "${YELLOW}=== Container Image Configuration ===${NC}"
read -p "Enter Docker image URI (e.g., 123456789.dkr.ecr.us-east-1.amazonaws.com/modresorts:latest): " IMAGE_URI
echo ""

# Ask about load balancer
echo -e "${YELLOW}=== Load Balancer Configuration ===${NC}"
read -p "Do you need a load balancer for this service? (y/n): " NEED_LB

if [[ "$NEED_LB" =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Creating Application Load Balancer and Target Group...${NC}"
    
    # Create ALB
    ALB_NAME="modresorts-alb"
    echo "Creating Application Load Balancer: $ALB_NAME"
    
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
    
    if [ -z "$ALB_ARN" ]; then
        echo -e "${RED}Error: Failed to create Application Load Balancer${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}ALB created successfully${NC}"
    echo "ALB ARN: $ALB_ARN"
    
    # Get ALB DNS name
    ALB_DNS=$(aws elbv2 describe-load-balancers \
        --load-balancer-arns "$ALB_ARN" \
        --region "$AWS_REGION" \
        --query 'LoadBalancers[0].DNSName' \
        --output text)
    
    # Create Target Group with target-type ip (required for Fargate)
    TG_NAME="modresorts-tg"
    echo "Creating Target Group: $TG_NAME"
    
    TARGET_GROUP_ARN=$(aws elbv2 create-target-group \
        --name "$TG_NAME" \
        --protocol HTTP \
        --port 8080 \
        --vpc-id "$VPC_ID" \
        --target-type ip \
        --health-check-enabled \
        --health-check-protocol HTTP \
        --health-check-path "/health" \
        --health-check-interval-seconds 30 \
        --health-check-timeout-seconds 5 \
        --healthy-threshold-count 2 \
        --unhealthy-threshold-count 3 \
        --region "$AWS_REGION" \
        --query 'TargetGroups[0].TargetGroupArn' \
        --output text)
    
    if [ -z "$TARGET_GROUP_ARN" ]; then
        echo -e "${RED}Error: Failed to create Target Group${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}Target Group created successfully${NC}"
    echo "Target Group ARN: $TARGET_GROUP_ARN"
    
    # Create listener
    echo "Creating ALB Listener..."
    aws elbv2 create-listener \
        --load-balancer-arn "$ALB_ARN" \
        --protocol HTTP \
        --port 80 \
        --default-actions Type=forward,TargetGroupArn="$TARGET_GROUP_ARN" \
        --region "$AWS_REGION" >/dev/null
    
    echo -e "${GREEN}ALB Listener created successfully${NC}"
    echo ""
    
    USE_LB=true
else
    echo -e "${YELLOW}Skipping load balancer configuration${NC}"
    USE_LB=false
fi

echo ""

# Create CloudWatch log group
echo -e "${YELLOW}Creating CloudWatch log group...${NC}"
LOG_GROUP="/ecs/$PROJECT_NAME"
aws logs create-log-group --log-group-name "$LOG_GROUP" --region "$AWS_REGION" 2>/dev/null || echo "Log group already exists"
echo -e "${GREEN}CloudWatch log group ready:${NC} $LOG_GROUP"
echo ""

# Update task definition JSON
echo -e "${YELLOW}Preparing task definition...${NC}"
TASK_DEF_FILE="ecs/task-definition.json"

# Replace placeholders in task definition
sed -i "s|{{IMAGE_URI}}|$IMAGE_URI|g" "$TASK_DEF_FILE"
sed -i "s|{{AWS_REGION}}|$AWS_REGION|g" "$TASK_DEF_FILE"
sed -i "s|{{ACCOUNT_ID}}|$ACCOUNT_ID|g" "$TASK_DEF_FILE"

# Register task definition
echo -e "${YELLOW}Registering task definition...${NC}"
TASK_DEF_ARN=$(aws ecs register-task-definition \
    --cli-input-json file://"$TASK_DEF_FILE" \
    --region "$AWS_REGION" \
    --query 'taskDefinition.taskDefinitionArn' \
    --output text)

if [ -z "$TASK_DEF_ARN" ]; then
    echo -e "${RED}Error: Failed to register task definition${NC}"
    exit 1
fi

echo -e "${GREEN}Task definition registered successfully${NC}"
echo "Task Definition ARN: $TASK_DEF_ARN"
echo ""

# Update service definition JSON
echo -e "${YELLOW}Preparing service definition...${NC}"
SERVICE_DEF_FILE="ecs/service-definition.json"

# Replace placeholders in service definition
sed -i "s|{{CLUSTER_NAME}}|$CLUSTER_NAME|g" "$SERVICE_DEF_FILE"
sed -i "s|{{SUBNET_1}}|$SUBNET_1|g" "$SERVICE_DEF_FILE"
sed -i "s|{{SUBNET_2}}|$SUBNET_2|g" "$SERVICE_DEF_FILE"
sed -i "s|{{SECURITY_GROUP}}|$SECURITY_GROUP|g" "$SERVICE_DEF_FILE"

if [ "$USE_LB" = true ]; then
    # Replace target group ARN
    sed -i "s|{{TARGET_GROUP_ARN}}|$TARGET_GROUP_ARN|g" "$SERVICE_DEF_FILE"
else
    # Remove loadBalancers section from service definition
    python3 -c "
import json
with open('$SERVICE_DEF_FILE', 'r') as f:
    data = json.load(f)
if 'loadBalancers' in data:
    del data['loadBalancers']
if 'healthCheckGracePeriodSeconds' in data:
    del data['healthCheckGracePeriodSeconds']
with open('$SERVICE_DEF_FILE', 'w') as f:
    json.dump(data, f, indent=2)
" 2>/dev/null || {
    # Fallback if Python is not available
    echo -e "${YELLOW}Warning: Could not remove loadBalancers section. Please ensure Python 3 is installed.${NC}"
}
fi

# Check if service exists
echo -e "${YELLOW}Checking if service exists...${NC}"
EXISTING_SERVICE=$(aws ecs describe-services \
    --cluster "$CLUSTER_NAME" \
    --services "$SERVICE_NAME" \
    --region "$AWS_REGION" \
    --query 'services[?status==`ACTIVE`].serviceName' \
    --output text 2>/dev/null)

if [ -z "$EXISTING_SERVICE" ] || [ "$EXISTING_SERVICE" == "None" ]; then
    # Create new service
    echo -e "${YELLOW}Creating new ECS service...${NC}"
    aws ecs create-service \
        --cli-input-json file://"$SERVICE_DEF_FILE" \
        --region "$AWS_REGION" >/dev/null
    
    echo -e "${GREEN}ECS service created successfully${NC}"
else
    # Update existing service
    echo -e "${YELLOW}Updating existing ECS service...${NC}"
    aws ecs update-service \
        --cluster "$CLUSTER_NAME" \
        --service "$SERVICE_NAME" \
        --task-definition "$TASK_DEF_ARN" \
        --force-new-deployment \
        --region "$AWS_REGION" >/dev/null
    
    echo -e "${GREEN}ECS service updated successfully${NC}"
fi

echo ""

# Wait for service to stabilize
echo -e "${YELLOW}Waiting for service to stabilize (this may take a few minutes)...${NC}"
aws ecs wait services-stable \
    --cluster "$CLUSTER_NAME" \
    --services "$SERVICE_NAME" \
    --region "$AWS_REGION"

echo -e "${GREEN}Service is stable${NC}"
echo ""

# Get service details
echo -e "${YELLOW}Retrieving service details...${NC}"
SERVICE_INFO=$(aws ecs describe-services \
    --cluster "$CLUSTER_NAME" \
    --services "$SERVICE_NAME" \
    --region "$AWS_REGION" \
    --query 'services[0]')

RUNNING_COUNT=$(echo "$SERVICE_INFO" | grep -o '"runningCount": [0-9]*' | grep -o '[0-9]*')
DESIRED_COUNT=$(echo "$SERVICE_INFO" | grep -o '"desiredCount": [0-9]*' | grep -o '[0-9]*')

echo ""
echo -e "${GREEN}=========================================="
echo -e "Deployment completed successfully!"
echo -e "==========================================${NC}"
echo ""
echo -e "${BLUE}Service Details:${NC}"
echo "  Cluster: $CLUSTER_NAME"
echo "  Service: $SERVICE_NAME"
echo "  Task Definition: $TASK_FAMILY"
echo "  Running Tasks: $RUNNING_COUNT / $DESIRED_COUNT"
echo "  Region: $AWS_REGION"
echo ""

if [ "$USE_LB" = true ]; then
    echo -e "${BLUE}Load Balancer:${NC}"
    echo "  DNS Name: $ALB_DNS"
    echo "  URL: http://$ALB_DNS"
    echo ""
fi

echo -e "${BLUE}CloudWatch Logs:${NC}"
echo "  Log Group: $LOG_GROUP"
echo "  View logs: aws logs tail $LOG_GROUP --follow --region $AWS_REGION"
echo ""

echo -e "${BLUE}Useful Commands:${NC}"
echo "  View service: aws ecs describe-services --cluster $CLUSTER_NAME --services $SERVICE_NAME --region $AWS_REGION"
echo "  List tasks: aws ecs list-tasks --cluster $CLUSTER_NAME --service-name $SERVICE_NAME --region $AWS_REGION"
echo "  Scale service: aws ecs update-service --cluster $CLUSTER_NAME --service $SERVICE_NAME --desired-count <count> --region $AWS_REGION"
echo ""
