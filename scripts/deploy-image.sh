#!/bin/bash

# Deploy ModResorts Backend to AWS ECS Fargate
# This script deploys the containerized application to AWS ECS

set -e
set -o pipefail

echo "=========================================="
echo "ModResorts Backend - ECS Fargate Deployment"
echo "=========================================="
echo ""

# Configuration
PROJECT_NAME="modresorts-backend"
TASK_FAMILY="modresorts-backend-task"
SERVICE_NAME="modresorts-backend-service"

# Prompt for AWS Region
read -p "Enter AWS Region (e.g., us-east-1): " AWS_REGION
export AWS_DEFAULT_REGION="$AWS_REGION"

echo ""
echo "Getting AWS Account ID..."
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "AWS Account ID: $ACCOUNT_ID"

# Prompt for ECS Cluster Name
echo ""
read -p "Enter ECS Cluster Name: " CLUSTER_NAME

# Check if cluster exists, create if not
echo ""
echo "Checking if ECS cluster exists..."
CLUSTER_EXISTS=$(aws ecs describe-clusters --clusters "$CLUSTER_NAME" --query 'clusters[0].clusterName' --output text 2>/dev/null || echo "None")

if [ "$CLUSTER_EXISTS" == "None" ] || [ -z "$CLUSTER_EXISTS" ]; then
    echo "Cluster does not exist. Creating ECS cluster: $CLUSTER_NAME"
    aws ecs create-cluster --cluster-name "$CLUSTER_NAME" --region "$AWS_REGION"
    echo "ECS cluster created successfully"
else
    echo "ECS cluster already exists: $CLUSTER_NAME"
fi

# Prompt for VPC and Network Configuration
echo ""
echo "=== Network Configuration ==="
read -p "Enter VPC ID: " VPC_ID
read -p "Enter Subnet ID 1: " SUBNET_1
read -p "Enter Subnet ID 2: " SUBNET_2
read -p "Enter Security Group ID: " SECURITY_GROUP

# Prompt for Docker Image URI
echo ""
read -p "Enter Docker Image URI (e.g., 123456789.dkr.ecr.us-east-1.amazonaws.com/modresorts-backend:latest): " IMAGE_URI

# Prompt for database configuration
echo ""
echo "=== Database Configuration ==="
read -p "Enter Database Host [localhost]: " DB_HOST
DB_HOST=${DB_HOST:-localhost}
read -p "Enter Database Port [5432]: " DB_PORT
DB_PORT=${DB_PORT:-5432}
read -p "Enter Database Name [modresorts]: " DB_NAME
DB_NAME=${DB_NAME:-modresorts}
read -p "Enter Database User [admin]: " DB_USER
DB_USER=${DB_USER:-admin}
read -sp "Enter Database Password: " DB_PASSWORD
echo ""

# Prompt for Load Balancer
echo ""
read -p "Do you need a load balancer for this service? (y/n): " NEED_LB

if [ "$NEED_LB" == "y" ] || [ "$NEED_LB" == "Y" ]; then
    echo ""
    echo "Creating Application Load Balancer and Target Group..."
    
    # Create Target Group
    echo "Creating Target Group..."
    TARGET_GROUP_ARN=$(aws elbv2 create-target-group \
        --name "${PROJECT_NAME}-tg" \
        --protocol HTTP \
        --port 8080 \
        --vpc-id "$VPC_ID" \
        --target-type ip \
        --health-check-enabled \
        --health-check-path "/health" \
        --health-check-interval-seconds 30 \
        --health-check-timeout-seconds 5 \
        --healthy-threshold-count 2 \
        --unhealthy-threshold-count 3 \
        --region "$AWS_REGION" \
        --query 'TargetGroups[0].TargetGroupArn' \
        --output text 2>/dev/null || echo "")
    
    if [ -z "$TARGET_GROUP_ARN" ]; then
        echo "Target Group may already exist. Fetching existing Target Group ARN..."
        TARGET_GROUP_ARN=$(aws elbv2 describe-target-groups \
            --names "${PROJECT_NAME}-tg" \
            --region "$AWS_REGION" \
            --query 'TargetGroups[0].TargetGroupArn' \
            --output text 2>/dev/null || echo "")
    fi
    
    if [ -z "$TARGET_GROUP_ARN" ]; then
        echo "ERROR: Failed to create or find Target Group"
        exit 1
    fi
    
    echo "Target Group ARN: $TARGET_GROUP_ARN"
    
    # Create Application Load Balancer
    echo "Creating Application Load Balancer..."
    ALB_ARN=$(aws elbv2 create-load-balancer \
        --name "${PROJECT_NAME}-alb" \
        --subnets "$SUBNET_1" "$SUBNET_2" \
        --security-groups "$SECURITY_GROUP" \
        --scheme internet-facing \
        --type application \
        --ip-address-type ipv4 \
        --region "$AWS_REGION" \
        --query 'LoadBalancers[0].LoadBalancerArn' \
        --output text 2>/dev/null || echo "")
    
    if [ -z "$ALB_ARN" ]; then
        echo "Load Balancer may already exist. Fetching existing ALB ARN..."
        ALB_ARN=$(aws elbv2 describe-load-balancers \
            --names "${PROJECT_NAME}-alb" \
            --region "$AWS_REGION" \
            --query 'LoadBalancers[0].LoadBalancerArn' \
            --output text 2>/dev/null || echo "")
    fi
    
    if [ -z "$ALB_ARN" ]; then
        echo "ERROR: Failed to create or find Application Load Balancer"
        exit 1
    fi
    
    echo "Application Load Balancer ARN: $ALB_ARN"
    
    # Create Listener
    echo "Creating ALB Listener..."
    LISTENER_ARN=$(aws elbv2 create-listener \
        --load-balancer-arn "$ALB_ARN" \
        --protocol HTTP \
        --port 80 \
        --default-actions Type=forward,TargetGroupArn="$TARGET_GROUP_ARN" \
        --region "$AWS_REGION" \
        --query 'Listeners[0].ListenerArn' \
        --output text 2>/dev/null || echo "")
    
    if [ -z "$LISTENER_ARN" ]; then
        echo "Listener may already exist. Continuing..."
    else
        echo "Listener created: $LISTENER_ARN"
    fi
    
    # Get ALB DNS Name
    ALB_DNS=$(aws elbv2 describe-load-balancers \
        --load-balancer-arns "$ALB_ARN" \
        --region "$AWS_REGION" \
        --query 'LoadBalancers[0].DNSName' \
        --output text)
    
    echo "Load Balancer DNS: $ALB_DNS"
else
    echo "Skipping load balancer creation"
    TARGET_GROUP_ARN=""
fi

# Create CloudWatch Log Group
echo ""
echo "Creating CloudWatch Log Group..."
aws logs create-log-group --log-group-name "/ecs/$PROJECT_NAME" --region "$AWS_REGION" 2>/dev/null || echo "Log group already exists"

# Update task definition with actual values
echo ""
echo "Preparing task definition..."
cp ecs/task-definition.json ecs/task-definition-temp.json

sed -i "s|{{ACCOUNT_ID}}|$ACCOUNT_ID|g" ecs/task-definition-temp.json
sed -i "s|{{IMAGE_URI}}|$IMAGE_URI|g" ecs/task-definition-temp.json
sed -i "s|{{AWS_REGION}}|$AWS_REGION|g" ecs/task-definition-temp.json
sed -i "s|{{DB_HOST}}|$DB_HOST|g" ecs/task-definition-temp.json
sed -i "s|{{DB_PORT}}|$DB_PORT|g" ecs/task-definition-temp.json
sed -i "s|{{DB_NAME}}|$DB_NAME|g" ecs/task-definition-temp.json
sed -i "s|{{DB_USER}}|$DB_USER|g" ecs/task-definition-temp.json
sed -i "s|{{DB_PASSWORD}}|$DB_PASSWORD|g" ecs/task-definition-temp.json

# Register task definition
echo ""
echo "Registering ECS task definition..."
TASK_DEFINITION_ARN=$(aws ecs register-task-definition \
    --cli-input-json file://ecs/task-definition-temp.json \
    --region "$AWS_REGION" \
    --query 'taskDefinition.taskDefinitionArn' \
    --output text)

echo "Task Definition registered: $TASK_DEFINITION_ARN"

# Clean up temporary file
rm -f ecs/task-definition-temp.json

# Update service definition with actual values
echo ""
echo "Preparing service definition..."
cp ecs/service-definition.json ecs/service-definition-temp.json

sed -i "s|{{CLUSTER_NAME}}|$CLUSTER_NAME|g" ecs/service-definition-temp.json
sed -i "s|{{SUBNET_1}}|$SUBNET_1|g" ecs/service-definition-temp.json
sed -i "s|{{SUBNET_2}}|$SUBNET_2|g" ecs/service-definition-temp.json
sed -i "s|{{SECURITY_GROUP}}|$SECURITY_GROUP|g" ecs/service-definition-temp.json

if [ -z "$TARGET_GROUP_ARN" ]; then
    # Remove loadBalancers section if no load balancer
    sed -i '/"loadBalancers":/,/],/d' ecs/service-definition-temp.json
    sed -i '/"healthCheckGracePeriodSeconds":/d' ecs/service-definition-temp.json
else
    sed -i "s|{{TARGET_GROUP_ARN}}|$TARGET_GROUP_ARN|g" ecs/service-definition-temp.json
fi

# Check if service exists
echo ""
echo "Checking if ECS service exists..."
SERVICE_EXISTS=$(aws ecs describe-services \
    --cluster "$CLUSTER_NAME" \
    --services "$SERVICE_NAME" \
    --region "$AWS_REGION" \
    --query 'services[0].serviceName' \
    --output text 2>/dev/null || echo "None")

if [ "$SERVICE_EXISTS" == "None" ] || [ -z "$SERVICE_EXISTS" ]; then
    echo "Service does not exist. Creating ECS service..."
    aws ecs create-service \
        --cli-input-json file://ecs/service-definition-temp.json \
        --region "$AWS_REGION"
    echo "ECS service created successfully"
else
    echo "Service already exists. Updating ECS service..."
    aws ecs update-service \
        --cluster "$CLUSTER_NAME" \
        --service "$SERVICE_NAME" \
        --task-definition "$TASK_DEFINITION_ARN" \
        --desired-count 2 \
        --region "$AWS_REGION"
    echo "ECS service updated successfully"
fi

# Clean up temporary file
rm -f ecs/service-definition-temp.json

# Wait for service to stabilize
echo ""
echo "Waiting for service to become stable (this may take a few minutes)..."
aws ecs wait services-stable \
    --cluster "$CLUSTER_NAME" \
    --services "$SERVICE_NAME" \
    --region "$AWS_REGION"

echo ""
echo "=========================================="
echo "Deployment Completed Successfully"
echo "=========================================="
echo ""
echo "Cluster: $CLUSTER_NAME"
echo "Service: $SERVICE_NAME"
echo "Task Definition: $TASK_DEFINITION_ARN"
echo "Region: $AWS_REGION"

if [ -n "$ALB_DNS" ]; then
    echo ""
    echo "Application URL: http://$ALB_DNS"
    echo "Health Check: http://$ALB_DNS/health"
fi

echo ""
echo "CloudWatch Logs: /ecs/$PROJECT_NAME"
echo ""
echo "To view service details:"
echo "aws ecs describe-services --cluster $CLUSTER_NAME --services $SERVICE_NAME --region $AWS_REGION"
echo ""
echo "To view running tasks:"
echo "aws ecs list-tasks --cluster $CLUSTER_NAME --service-name $SERVICE_NAME --region $AWS_REGION"
echo ""
