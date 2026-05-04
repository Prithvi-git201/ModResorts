#!/bin/bash

# ECS Fargate Deployment Script for ModResorts Application
# Deploys containerized application to AWS ECS Fargate

set -e
set -o pipefail

echo "=========================================="
echo "ModResorts - ECS Fargate Deployment"
echo "=========================================="
echo ""

# Prompt for AWS region
read -p "Enter AWS region (e.g., us-east-1): " AWS_REGION
if [ -z "$AWS_REGION" ]; then
    echo "Error: AWS region is required"
    exit 1
fi

# Prompt for ECS cluster name
read -p "Enter ECS cluster name: " CLUSTER_NAME
if [ -z "$CLUSTER_NAME" ]; then
    echo "Error: ECS cluster name is required"
    exit 1
fi

# Prompt for VPC ID
read -p "Enter VPC ID: " VPC_ID
if [ -z "$VPC_ID" ]; then
    echo "Error: VPC ID is required"
    exit 1
fi

# Prompt for subnet IDs (comma-separated)
read -p "Enter subnet IDs (comma-separated, at least 2): " SUBNETS_INPUT
if [ -z "$SUBNETS_INPUT" ]; then
    echo "Error: At least 2 subnet IDs are required for high availability"
    exit 1
fi

# Parse subnets
IFS=',' read -ra SUBNET_ARRAY <<< "$SUBNETS_INPUT"
SUBNET_1=$(echo "${SUBNET_ARRAY[0]}" | xargs)
SUBNET_2=$(echo "${SUBNET_ARRAY[1]}" | xargs)

if [ -z "$SUBNET_1" ] || [ -z "$SUBNET_2" ]; then
    echo "Error: At least 2 subnet IDs are required"
    exit 1
fi

# Prompt for security group ID
read -p "Enter security group ID (must allow inbound traffic on port 8080): " SECURITY_GROUP
if [ -z "$SECURITY_GROUP" ]; then
    echo "Error: Security group ID is required"
    exit 1
fi

# Prompt for ECR image URI
read -p "Enter ECR image URI (e.g., 123456789.dkr.ecr.us-east-1.amazonaws.com/modresorts:latest): " IMAGE_URI
if [ -z "$IMAGE_URI" ]; then
    echo "Error: Image URI is required"
    exit 1
fi

# Get AWS Account ID
echo ""
echo "Getting AWS account ID..."
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
if [ -z "$ACCOUNT_ID" ]; then
    echo "Error: Failed to get AWS account ID"
    exit 1
fi
echo "AWS Account ID: $ACCOUNT_ID"

# Check if ECS cluster exists, create if not
echo ""
echo "Checking if ECS cluster exists..."
aws ecs describe-clusters --clusters "$CLUSTER_NAME" --region "$AWS_REGION" >/dev/null 2>&1 || {
    echo "Cluster does not exist. Creating ECS cluster: $CLUSTER_NAME"
    aws ecs create-cluster --cluster-name "$CLUSTER_NAME" --region "$AWS_REGION"
    if [ $? -ne 0 ]; then
        echo "Error: Failed to create ECS cluster"
        exit 1
    fi
}

# Prompt for load balancer
echo ""
read -p "Do you need a load balancer for this service? (y/n): " NEED_LB

if [[ "$NEED_LB" =~ ^[Yy]$ ]]; then
    echo ""
    echo "Creating Application Load Balancer and Target Group..."
    
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
        echo "Error: Failed to create Application Load Balancer"
        exit 1
    fi
    echo "ALB created: $ALB_ARN"
    
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
        echo "Error: Failed to create Target Group"
        exit 1
    fi
    echo "Target Group created: $TARGET_GROUP_ARN"
    
    # Create Listener
    echo "Creating ALB Listener..."
    aws elbv2 create-listener \
        --load-balancer-arn "$ALB_ARN" \
        --protocol HTTP \
        --port 80 \
        --default-actions Type=forward,TargetGroupArn="$TARGET_GROUP_ARN" \
        --region "$AWS_REGION" >/dev/null
    
    echo "Load balancer setup complete"
    
    # Update service definition with load balancer
    sed -i "s|{{TARGET_GROUP_ARN}}|$TARGET_GROUP_ARN|g" ecs/service-definition.json
else
    echo "Skipping load balancer creation"
    # Remove loadBalancers section from service definition
    python3 -c "
import json
with open('ecs/service-definition.json', 'r') as f:
    data = json.load(f)
if 'loadBalancers' in data:
    del data['loadBalancers']
if 'healthCheckGracePeriodSeconds' in data:
    del data['healthCheckGracePeriodSeconds']
with open('ecs/service-definition.json', 'w') as f:
    json.dump(data, f, indent=2)
" 2>/dev/null || {
        # Fallback if python3 is not available
        echo "Warning: Could not remove loadBalancers section. Please edit service-definition.json manually."
    }
fi

# Create CloudWatch log group
echo ""
echo "Creating CloudWatch log group..."
aws logs create-log-group --log-group-name "/ecs/modresorts" --region "$AWS_REGION" 2>/dev/null || echo "Log group already exists"

# Replace placeholders in task definition
echo ""
echo "Preparing task definition..."
cp ecs/task-definition.json ecs/task-definition-temp.json
sed -i "s|{{IMAGE_URI}}|$IMAGE_URI|g" ecs/task-definition-temp.json
sed -i "s|{{AWS_REGION}}|$AWS_REGION|g" ecs/task-definition-temp.json
sed -i "s|{{ACCOUNT_ID}}|$ACCOUNT_ID|g" ecs/task-definition-temp.json
sed -i "s|{{DB_HOST}}|localhost|g" ecs/task-definition-temp.json
sed -i "s|{{DB_PORT}}|5432|g" ecs/task-definition-temp.json
sed -i "s|{{DB_NAME}}|modresorts|g" ecs/task-definition-temp.json
sed -i "s|{{DB_USER}}|admin|g" ecs/task-definition-temp.json
sed -i "s|{{DB_PASSWORD}}|changeme|g" ecs/task-definition-temp.json

# Register task definition
echo "Registering ECS task definition..."
TASK_DEF_ARN=$(aws ecs register-task-definition \
    --cli-input-json file://ecs/task-definition-temp.json \
    --region "$AWS_REGION" \
    --query 'taskDefinition.taskDefinitionArn' \
    --output text)

if [ -z "$TASK_DEF_ARN" ]; then
    echo "Error: Failed to register task definition"
    rm -f ecs/task-definition-temp.json
    exit 1
fi

echo "Task definition registered: $TASK_DEF_ARN"
rm -f ecs/task-definition-temp.json

# Replace placeholders in service definition
echo ""
echo "Preparing service definition..."
cp ecs/service-definition.json ecs/service-definition-temp.json
sed -i "s|{{CLUSTER_NAME}}|$CLUSTER_NAME|g" ecs/service-definition-temp.json
sed -i "s|{{SUBNET_1}}|$SUBNET_1|g" ecs/service-definition-temp.json
sed -i "s|{{SUBNET_2}}|$SUBNET_2|g" ecs/service-definition-temp.json
sed -i "s|{{SECURITY_GROUP}}|$SECURITY_GROUP|g" ecs/service-definition-temp.json

# Check if service exists
SERVICE_NAME="modresorts-service"
echo "Checking if service exists..."
EXISTING_SERVICE=$(aws ecs describe-services \
    --cluster "$CLUSTER_NAME" \
    --services "$SERVICE_NAME" \
    --region "$AWS_REGION" \
    --query 'services[?status==`ACTIVE`].serviceName' \
    --output text)

if [ -z "$EXISTING_SERVICE" ] || [ "$EXISTING_SERVICE" == "None" ]; then
    # Create new service
    echo "Creating new ECS service..."
    aws ecs create-service \
        --cli-input-json file://ecs/service-definition-temp.json \
        --region "$AWS_REGION" >/dev/null
    
    if [ $? -ne 0 ]; then
        echo "Error: Failed to create ECS service"
        rm -f ecs/service-definition-temp.json
        exit 1
    fi
    echo "Service created successfully"
else
    # Update existing service
    echo "Updating existing ECS service..."
    aws ecs update-service \
        --cluster "$CLUSTER_NAME" \
        --service "$SERVICE_NAME" \
        --task-definition "$TASK_DEF_ARN" \
        --desired-count 2 \
        --region "$AWS_REGION" >/dev/null
    
    if [ $? -ne 0 ]; then
        echo "Error: Failed to update ECS service"
        rm -f ecs/service-definition-temp.json
        exit 1
    fi
    echo "Service updated successfully"
fi

rm -f ecs/service-definition-temp.json

# Wait for service to stabilize
echo ""
echo "Waiting for service to stabilize (this may take a few minutes)..."
aws ecs wait services-stable \
    --cluster "$CLUSTER_NAME" \
    --services "$SERVICE_NAME" \
    --region "$AWS_REGION"

if [ $? -ne 0 ]; then
    echo "Warning: Service did not stabilize within the expected time"
else
    echo "Service is stable"
fi

# Verify deployment
echo ""
echo "=========================================="
echo "Deployment Summary"
echo "=========================================="
aws ecs describe-services \
    --cluster "$CLUSTER_NAME" \
    --services "$SERVICE_NAME" \
    --region "$AWS_REGION" \
    --query 'services[0].[serviceName,status,runningCount,desiredCount]' \
    --output table

echo ""
echo "CloudWatch Logs: /ecs/modresorts"
echo "Region: $AWS_REGION"

if [[ "$NEED_LB" =~ ^[Yy]$ ]]; then
    echo ""
    echo "Application Load Balancer DNS: $ALB_DNS"
    echo "Access your application at: http://$ALB_DNS"
fi

echo ""
echo "=========================================="
echo "✓ Deployment Complete!"
echo "=========================================="
