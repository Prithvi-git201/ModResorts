# ModResorts Application - AWS ECS Fargate Deployment Guide

## Table of Contents
1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Local Development Setup](#local-development-setup)
4. [Building and Pushing Docker Images](#building-and-pushing-docker-images)
5. [AWS ECS Fargate Prerequisites](#aws-ecs-fargate-prerequisites)
6. [ECS Fargate Setup](#ecs-fargate-setup)
7. [ECS Task Definition Explained](#ecs-task-definition-explained)
8. [ECS Service Configuration](#ecs-service-configuration)
9. [Deployment Walkthrough](#deployment-walkthrough)
10. [Troubleshooting](#troubleshooting)
11. [Scaling and Management](#scaling-and-management)
12. [Security Considerations](#security-considerations)
13. [Monitoring and Logging](#monitoring-and-logging)

---

## Overview

ModResorts is a Java 8 web application packaged as a WAR file, running on Apache Tomcat 9 in a containerized environment. This guide covers deploying the application to AWS ECS Fargate, a serverless container orchestration platform.

**Application Details:**
- **Technology Stack**: Java 8, Servlet API, Maven
- **Package Type**: WAR (Web Application Archive)
- **Runtime**: Apache Tomcat 9
- **Application Port**: 8080
- **Health Endpoints**: `/health`, `/health/live`, `/health/ready`
- **Base Image**: Eclipse Temurin 8 JDK

---

## Prerequisites

### Required Software
- **Docker**: Version 20.10 or higher
- **Docker Compose**: Version 1.29 or higher (for local development)
- **AWS CLI**: Version 2.x
- **Git**: For version control
- **Java 8 JDK**: For local development (optional)
- **Maven 3.6+**: For local builds (optional)

### AWS Account Requirements
- Active AWS account with appropriate permissions
- IAM user with permissions for:
  - ECS (Elastic Container Service)
  - ECR (Elastic Container Registry)
  - EC2 (for VPC, subnets, security groups)
  - IAM (for role creation)
  - CloudWatch Logs
  - Elastic Load Balancing (optional)

### AWS CLI Configuration
```bash
# Configure AWS CLI with your credentials
aws configure

# Verify configuration
aws sts get-caller-identity
```

---

## Local Development Setup

### 1. Clone the Repository
```bash
git clone <repository-url>
cd fullcomp
```

### 2. Build Locally with Maven (Optional)
```bash
# Build the WAR file
mvn clean package -DskipTests

# The WAR file will be in target/modresorts-2.0.0.war
```

### 3. Run with Docker Compose
```bash
# Build and start the application
docker-compose up --build

# Access the application
# http://localhost:8080

# Stop the application
docker-compose down
```

### 4. Test Health Endpoints
```bash
# Basic health check
curl http://localhost:8080/health

# Liveness probe
curl http://localhost:8080/health/live

# Readiness probe
curl http://localhost:8080/health/ready
```

---

## Building and Pushing Docker Images

### Option 1: Using build-push.sh (Linux/macOS)

```bash
# Make the script executable
chmod +x scripts/build-push.sh

# Run the script
./scripts/build-push.sh
```

**Script Workflow:**
1. Prompts for image tag (default: latest)
2. Asks to select registry (AWS ECR or Docker Hub)
3. Collects registry-specific credentials
4. Builds the Docker image
5. Pushes to the selected registry

### Option 2: Using build-push.bat (Windows)

```cmd
# Run the script
scripts\build-push.bat
```

### Manual Build and Push

#### For AWS ECR:
```bash
# Set variables
AWS_REGION="us-east-1"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REPO="modresorts"
IMAGE_TAG="latest"

# Login to ECR
aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin \
  $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

# Create repository (if not exists)
aws ecr create-repository --repository-name $ECR_REPO --region $AWS_REGION

# Build image
docker build -t $ECR_REPO:$IMAGE_TAG .

# Tag image
docker tag $ECR_REPO:$IMAGE_TAG \
  $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPO:$IMAGE_TAG

# Push image
docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPO:$IMAGE_TAG
```

#### For Docker Hub:
```bash
# Login to Docker Hub
docker login

# Build and tag
docker build -t <username>/modresorts:latest .

# Push
docker push <username>/modresorts:latest
```

---

## AWS ECS Fargate Prerequisites

### 1. VPC Configuration

You need a VPC with at least 2 subnets in different availability zones for high availability.

**Create VPC (if needed):**
```bash
# Create VPC
aws ec2 create-vpc --cidr-block 10.0.0.0/16 --region us-east-1

# Create subnets
aws ec2 create-subnet --vpc-id <vpc-id> --cidr-block 10.0.1.0/24 --availability-zone us-east-1a
aws ec2 create-subnet --vpc-id <vpc-id> --cidr-block 10.0.2.0/24 --availability-zone us-east-1b

# Create internet gateway
aws ec2 create-internet-gateway
aws ec2 attach-internet-gateway --vpc-id <vpc-id> --internet-gateway-id <igw-id>
```

### 2. Security Group Configuration

Create a security group that allows inbound traffic on port 8080:

```bash
# Create security group
aws ec2 create-security-group \
  --group-name modresorts-sg \
  --description "Security group for ModResorts application" \
  --vpc-id <vpc-id>

# Allow inbound traffic on port 8080
aws ec2 authorize-security-group-ingress \
  --group-id <sg-id> \
  --protocol tcp \
  --port 8080 \
  --cidr 0.0.0.0/0

# Allow inbound traffic on port 80 (if using ALB)
aws ec2 authorize-security-group-ingress \
  --group-id <sg-id> \
  --protocol tcp \
  --port 80 \
  --cidr 0.0.0.0/0
```

### 3. IAM Roles

#### ECS Task Execution Role
This role allows ECS to pull images from ECR and write logs to CloudWatch.

```bash
# Create trust policy file
cat > ecs-task-execution-trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs-tasks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

# Create role
aws iam create-role \
  --role-name ecsTaskExecutionRole \
  --assume-role-policy-document file://ecs-task-execution-trust-policy.json

# Attach AWS managed policy
aws iam attach-role-policy \
  --role-name ecsTaskExecutionRole \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy
```

#### ECS Task Role (Optional)
This role grants permissions to the application itself (e.g., to access S3, DynamoDB).

```bash
# Create task role
aws iam create-role \
  --role-name ecsTaskRole \
  --assume-role-policy-document file://ecs-task-execution-trust-policy.json

# Attach policies as needed (example: S3 read access)
aws iam attach-role-policy \
  --role-name ecsTaskRole \
  --policy-arn arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess
```

---

## ECS Fargate Setup

### 1. Create ECS Cluster

```bash
aws ecs create-cluster --cluster-name modresorts-cluster --region us-east-1
```

### 2. Create CloudWatch Log Group

```bash
aws logs create-log-group --log-group-name /ecs/modresorts --region us-east-1
```

---

## ECS Task Definition Explained

The task definition (`ecs/task-definition.json`) defines how your container should run.

### Key Components:

#### Fargate Configuration
```json
{
  "requiresCompatibilities": ["FARGATE"],
  "networkMode": "awsvpc",
  "cpu": "512",
  "memory": "1024"
}
```

**Valid Fargate CPU/Memory Combinations:**
- CPU: 256 (.25 vCPU) → Memory: 512, 1024, 2048 MB
- CPU: 512 (.5 vCPU) → Memory: 1024, 2048, 3072, 4096 MB
- CPU: 1024 (1 vCPU) → Memory: 2048-8192 MB (increments of 1024)
- CPU: 2048 (2 vCPU) → Memory: 4096-16384 MB
- CPU: 4096 (4 vCPU) → Memory: 8192-30720 MB

#### Container Definition
```json
{
  "name": "modresorts",
  "image": "{{IMAGE_URI}}",
  "essential": true,
  "portMappings": [
    {
      "containerPort": 8080,
      "protocol": "tcp"
    }
  ]
}
```

#### Environment Variables
```json
{
  "environment": [
    {
      "name": "JAVA_OPTS",
      "value": "-Xmx512m -Xms256m -XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0"
    }
  ]
}
```

#### Logging Configuration
```json
{
  "logConfiguration": {
    "logDriver": "awslogs",
    "options": {
      "awslogs-group": "/ecs/modresorts",
      "awslogs-region": "us-east-1",
      "awslogs-stream-prefix": "ecs"
    }
  }
}
```

---

## ECS Service Configuration

The service definition (`ecs/service-definition.json`) manages the deployment and scaling of your tasks.

### Key Components:

#### Fargate Launch Type
```json
{
  "launchType": "FARGATE",
  "desiredCount": 2
}
```

#### Network Configuration
```json
{
  "networkConfiguration": {
    "awsvpcConfiguration": {
      "subnets": ["subnet-xxx", "subnet-yyy"],
      "securityGroups": ["sg-xxx"],
      "assignPublicIp": "ENABLED"
    }
  }
}
```

#### Deployment Configuration
```json
{
  "deploymentConfiguration": {
    "maximumPercent": 200,
    "minimumHealthyPercent": 50
  }
}
```

#### Load Balancer (Optional)
```json
{
  "loadBalancers": [
    {
      "targetGroupArn": "arn:aws:elasticloadbalancing:...",
      "containerName": "modresorts",
      "containerPort": 8080
    }
  ],
  "healthCheckGracePeriodSeconds": 300
}
```

---

## Deployment Walkthrough

### Automated Deployment

#### Linux/macOS:
```bash
# Make the script executable
chmod +x scripts/deploy-image.sh

# Run the deployment script
./scripts/deploy-image.sh
```

#### Windows:
```cmd
# Run the deployment script
scripts\deploy-image.bat
```

### Script Workflow:

1. **Prompts for Configuration:**
   - AWS region
   - ECS cluster name
   - VPC ID
   - Subnet IDs (comma-separated)
   - Security group ID
   - ECR image URI

2. **Load Balancer Setup (Optional):**
   - Asks if you need a load balancer
   - If yes, automatically creates:
     - Application Load Balancer
     - Target Group (with target-type: ip)
     - Listener on port 80

3. **Task Definition Registration:**
   - Replaces placeholders in task definition
   - Registers task definition with ECS

4. **Service Creation/Update:**
   - Checks if service exists
   - Creates new service or updates existing one
   - Waits for service to stabilize

5. **Verification:**
   - Displays service status
   - Shows CloudWatch log group
   - Provides ALB DNS (if created)

### Manual Deployment Steps

#### 1. Register Task Definition
```bash
# Replace placeholders in task-definition.json
# Then register:
aws ecs register-task-definition \
  --cli-input-json file://ecs/task-definition.json \
  --region us-east-1
```

#### 2. Create Service
```bash
aws ecs create-service \
  --cli-input-json file://ecs/service-definition.json \
  --region us-east-1
```

#### 3. Update Service (for redeployment)
```bash
aws ecs update-service \
  --cluster modresorts-cluster \
  --service modresorts-service \
  --task-definition modresorts-task:2 \
  --force-new-deployment \
  --region us-east-1
```

---

## Troubleshooting

### Common Issues and Solutions

#### 1. Task Fails to Start

**Symptoms:**
- Tasks transition from PENDING to STOPPED
- No running tasks in the service

**Possible Causes:**
- Invalid CPU/memory combination
- Image pull errors
- Insufficient IAM permissions

**Solutions:**
```bash
# Check task stopped reason
aws ecs describe-tasks \
  --cluster modresorts-cluster \
  --tasks <task-id> \
  --region us-east-1 \
  --query 'tasks[0].stoppedReason'

# Check CloudWatch logs
aws logs tail /ecs/modresorts --follow --region us-east-1

# Verify IAM role permissions
aws iam get-role --role-name ecsTaskExecutionRole
```

#### 2. Network Issues

**Symptoms:**
- Cannot access application
- Health checks failing

**Solutions:**
```bash
# Verify security group rules
aws ec2 describe-security-groups --group-ids <sg-id>

# Check if subnets have internet access
aws ec2 describe-route-tables --filters "Name=association.subnet-id,Values=<subnet-id>"

# Verify task has public IP (if assignPublicIp: ENABLED)
aws ecs describe-tasks \
  --cluster modresorts-cluster \
  --tasks <task-id> \
  --region us-east-1 \
  --query 'tasks[0].attachments[0].details'
```

#### 3. CPU/Memory Errors

**Error Message:**
```
Invalid CPU or memory value specified
```

**Solution:**
Use valid Fargate CPU/memory combinations. Update `ecs/task-definition.json`:
```json
{
  "cpu": "512",
  "memory": "1024"
}
```

#### 4. Image Pull Errors

**Error Message:**
```
CannotPullContainerError: Error response from daemon
```

**Solutions:**
```bash
# Verify image exists in ECR
aws ecr describe-images \
  --repository-name modresorts \
  --region us-east-1

# Check execution role has ECR permissions
aws iam list-attached-role-policies --role-name ecsTaskExecutionRole

# Verify image URI format
# Correct: 123456789.dkr.ecr.us-east-1.amazonaws.com/modresorts:latest
```

#### 5. Health Check Failures

**Symptoms:**
- Tasks start but are marked unhealthy
- Load balancer shows targets as unhealthy

**Solutions:**
```bash
# Test health endpoint directly
curl http://<task-public-ip>:8080/health

# Check health check configuration in target group
aws elbv2 describe-target-health \
  --target-group-arn <tg-arn>

# Increase health check grace period
aws ecs update-service \
  --cluster modresorts-cluster \
  --service modresorts-service \
  --health-check-grace-period-seconds 300
```

#### 6. Application Logs

**View logs in CloudWatch:**
```bash
# Tail logs
aws logs tail /ecs/modresorts --follow --region us-east-1

# Filter logs
aws logs filter-log-events \
  --log-group-name /ecs/modresorts \
  --filter-pattern "ERROR" \
  --region us-east-1
```

---

## Scaling and Management

### Manual Scaling

```bash
# Scale to 5 tasks
aws ecs update-service \
  --cluster modresorts-cluster \
  --service modresorts-service \
  --desired-count 5 \
  --region us-east-1
```

### Auto Scaling

#### 1. Register Scalable Target
```bash
aws application-autoscaling register-scalable-target \
  --service-namespace ecs \
  --resource-id service/modresorts-cluster/modresorts-service \
  --scalable-dimension ecs:service:DesiredCount \
  --min-capacity 2 \
  --max-capacity 10 \
  --region us-east-1
```

#### 2. Create Scaling Policy (Target Tracking)
```bash
aws application-autoscaling put-scaling-policy \
  --service-namespace ecs \
  --resource-id service/modresorts-cluster/modresorts-service \
  --scalable-dimension ecs:service:DesiredCount \
  --policy-name cpu-target-tracking \
  --policy-type TargetTrackingScaling \
  --target-tracking-scaling-policy-configuration file://scaling-policy.json \
  --region us-east-1
```

**scaling-policy.json:**
```json
{
  "TargetValue": 70.0,
  "PredefinedMetricSpecification": {
    "PredefinedMetricType": "ECSServiceAverageCPUUtilization"
  },
  "ScaleInCooldown": 300,
  "ScaleOutCooldown": 60
}
```

### Blue/Green Deployments

For zero-downtime deployments, use AWS CodeDeploy with ECS:

```bash
# Create deployment group
aws deploy create-deployment-group \
  --application-name modresorts-app \
  --deployment-group-name modresorts-dg \
  --deployment-config-name CodeDeployDefault.ECSAllAtOnce \
  --service-role-arn <codedeploy-role-arn> \
  --ecs-services clusterName=modresorts-cluster,serviceName=modresorts-service \
  --load-balancer-info targetGroupInfoList=[{name=modresorts-tg}]
```

---

## Security Considerations

### 1. Use Secrets Manager for Sensitive Data

Instead of environment variables, use AWS Secrets Manager:

```json
{
  "secrets": [
    {
      "name": "DB_PASSWORD",
      "valueFrom": "arn:aws:secretsmanager:us-east-1:123456789:secret:db-password"
    }
  ]
}
```

### 2. Enable Container Insights

```bash
aws ecs update-cluster-settings \
  --cluster modresorts-cluster \
  --settings name=containerInsights,value=enabled \
  --region us-east-1
```

### 3. Use Private Subnets with NAT Gateway

For production, place tasks in private subnets and use NAT Gateway for outbound internet access.

### 4. Implement Network Policies

Use security groups to restrict traffic between services.

### 5. Enable VPC Flow Logs

```bash
aws ec2 create-flow-logs \
  --resource-type VPC \
  --resource-ids <vpc-id> \
  --traffic-type ALL \
  --log-destination-type cloud-watch-logs \
  --log-group-name /aws/vpc/flowlogs
```

---

## Monitoring and Logging

### CloudWatch Metrics

Key metrics to monitor:
- **CPUUtilization**: Average CPU usage
- **MemoryUtilization**: Average memory usage
- **TargetResponseTime**: Application response time
- **HealthyHostCount**: Number of healthy targets

### CloudWatch Alarms

```bash
# Create CPU alarm
aws cloudwatch put-metric-alarm \
  --alarm-name modresorts-high-cpu \
  --alarm-description "Alert when CPU exceeds 80%" \
  --metric-name CPUUtilization \
  --namespace AWS/ECS \
  --statistic Average \
  --period 300 \
  --threshold 80 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 2 \
  --dimensions Name=ServiceName,Value=modresorts-service Name=ClusterName,Value=modresorts-cluster
```

### Application Performance Monitoring

Consider integrating APM tools:
- AWS X-Ray for distributed tracing
- New Relic, Datadog, or Dynatrace for comprehensive monitoring

### Log Aggregation

Use CloudWatch Logs Insights for log analysis:

```sql
fields @timestamp, @message
| filter @message like /ERROR/
| sort @timestamp desc
| limit 100
```

---

## Additional Resources

- [AWS ECS Documentation](https://docs.aws.amazon.com/ecs/)
- [AWS Fargate Documentation](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/AWS_Fargate.html)
- [Docker Best Practices](https://docs.docker.com/develop/dev-best-practices/)
- [Java Container Best Practices](https://docs.oracle.com/en/java/javase/11/docs/api/java.base/java/lang/Runtime.html)

---

## Support and Contribution

For issues, questions, or contributions, please refer to the project repository.

**Version**: 2.0.0  
**Last Updated**: 2024
