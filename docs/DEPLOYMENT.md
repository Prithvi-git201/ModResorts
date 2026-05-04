# ModResorts Backend - Deployment Guide

## Table of Contents
1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Local Development Setup](#local-development-setup)
4. [Docker Deployment](#docker-deployment)
5. [AWS ECS Fargate Deployment](#aws-ecs-fargate-deployment)
6. [Configuration Management](#configuration-management)
7. [Troubleshooting](#troubleshooting)
8. [Security Considerations](#security-considerations)
9. [Monitoring and Logging](#monitoring-and-logging)

---

## Overview

ModResorts Backend is a JavaEE 7 web application packaged as a WAR file. This guide covers containerization and deployment to AWS ECS Fargate.

**Technology Stack:**
- Java 8
- JavaEE 7 (Servlets, Filters)
- Maven 3.9.4
- Apache Tomcat 9.0
- WAR packaging

**Application Details:**
- **Port:** 8080
- **Health Endpoint:** `/health` and `/actuator/health`
- **Context Path:** `/` (ROOT deployment)

---

## Prerequisites

### Required Tools
- **Docker** (version 20.10 or higher)
- **Docker Compose** (version 1.29 or higher)
- **AWS CLI** (version 2.x)
- **Git** (for version control)
- **Maven** (version 3.6 or higher) - for local builds

### AWS Requirements
- AWS Account with appropriate permissions
- IAM roles configured:
  - `ecsTaskExecutionRole` - for ECS to pull images and write logs
  - `ecsTaskRole` - for application permissions (optional)
- VPC with at least 2 subnets in different availability zones
- Security groups configured to allow:
  - Inbound: Port 8080 (application)
  - Outbound: All traffic (for external dependencies)

### AWS CLI Configuration
```bash
# Configure AWS CLI
aws configure

# Verify configuration
aws sts get-caller-identity
```

---

## Local Development Setup

### 1. Clone the Repository
```bash
git clone <repository-url>
cd ModResortsBackEnd
```

### 2. Build Locally with Maven
```bash
# Clean and build
mvn clean package

# The WAR file will be generated at:
# target/modresorts-2.0.0.war
```

### 3. Run with Docker Compose
```bash
# Build and start the application
docker-compose up --build

# Access the application
# http://localhost:8080

# Health check
# http://localhost:8080/health

# Stop the application
docker-compose down
```

### 4. Environment Variables
Create a `.env` file in the project root:
```env
DB_HOST=localhost
DB_PORT=5432
DB_NAME=modresorts
DB_USER=admin
DB_PASSWORD=changeme
```

---

## Docker Deployment

### Build Docker Image Manually
```bash
# Build the image
docker build -t modresorts-backend:latest .

# Run the container
docker run -d \
  -p 8080:8080 \
  -e JAVA_OPTS="-Xmx512m -Xms256m" \
  -e DB_HOST=localhost \
  -e DB_PORT=5432 \
  -e DB_NAME=modresorts \
  -e DB_USER=admin \
  -e DB_PASSWORD=changeme \
  --name modresorts-backend \
  modresorts-backend:latest

# View logs
docker logs -f modresorts-backend

# Stop and remove
docker stop modresorts-backend
docker rm modresorts-backend
```

### Build and Push to Registry

#### Option 1: AWS ECR
```bash
# Linux/macOS
./scripts/build-push.sh

# Windows
scripts\build-push.bat

# Follow the prompts:
# 1. Select AWS ECR
# 2. Enter AWS Region (e.g., us-east-1)
# 3. Enter AWS Account ID
# 4. Enter ECR Repository Name (default: modresorts-backend)
# 5. Enter image tag (default: latest)
```

#### Option 2: Docker Hub
```bash
# Linux/macOS
./scripts/build-push.sh

# Windows
scripts\build-push.bat

# Follow the prompts:
# 1. Select Docker Hub
# 2. Enter Docker Hub Username
# 3. Enter Docker Hub Password
# 4. Enter image tag (default: latest)
```

---

## AWS ECS Fargate Deployment

### Architecture Overview
```
┌─────────────────────────────────────────────────────────┐
│                    Application Load Balancer            │
│                    (Port 80 → 8080)                     │
└────────────────────┬────────────────────────────────────┘
                     │
         ┌───────────┴───────────┐
         │                       │
    ┌────▼────┐            ┌────▼────┐
    │  Task 1 │            │  Task 2 │
    │ (Fargate)│            │ (Fargate)│
    └─────────┘            └─────────┘
         │                       │
         └───────────┬───────────┘
                     │
              ┌──────▼──────┐
              │  CloudWatch │
              │    Logs     │
              └─────────────┘
```

### Step 1: Prepare AWS Infrastructure

#### Create VPC and Subnets (if not exists)
```bash
# Create VPC
aws ec2 create-vpc \
  --cidr-block 10.0.0.0/16 \
  --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=modresorts-vpc}]'

# Create Subnets
aws ec2 create-subnet \
  --vpc-id <vpc-id> \
  --cidr-block 10.0.1.0/24 \
  --availability-zone us-east-1a

aws ec2 create-subnet \
  --vpc-id <vpc-id> \
  --cidr-block 10.0.2.0/24 \
  --availability-zone us-east-1b
```

#### Create Security Group
```bash
# Create security group
aws ec2 create-security-group \
  --group-name modresorts-sg \
  --description "Security group for ModResorts Backend" \
  --vpc-id <vpc-id>

# Allow inbound traffic on port 8080
aws ec2 authorize-security-group-ingress \
  --group-id <security-group-id> \
  --protocol tcp \
  --port 8080 \
  --cidr 0.0.0.0/0

# Allow inbound traffic on port 80 (for ALB)
aws ec2 authorize-security-group-ingress \
  --group-id <security-group-id> \
  --protocol tcp \
  --port 80 \
  --cidr 0.0.0.0/0
```

#### Create IAM Roles

**ECS Task Execution Role:**
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

# Attach managed policy
aws iam attach-role-policy \
  --role-name ecsTaskExecutionRole \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy
```

### Step 2: Build and Push Docker Image
```bash
# Linux/macOS
./scripts/build-push.sh

# Windows
scripts\build-push.bat

# Select AWS ECR and provide:
# - AWS Region
# - AWS Account ID
# - ECR Repository Name
# - Image Tag
```

### Step 3: Deploy to ECS Fargate
```bash
# Linux/macOS
./scripts/deploy-image.sh

# Windows
scripts\deploy-image.bat

# Provide the following information when prompted:
# 1. AWS Region (e.g., us-east-1)
# 2. ECS Cluster Name (will be created if doesn't exist)
# 3. VPC ID
# 4. Subnet ID 1
# 5. Subnet ID 2
# 6. Security Group ID
# 7. Docker Image URI (from ECR)
# 8. Database Configuration:
#    - DB Host
#    - DB Port
#    - DB Name
#    - DB User
#    - DB Password
# 9. Load Balancer (y/n)
```

### Step 4: Verify Deployment
```bash
# Check service status
aws ecs describe-services \
  --cluster <cluster-name> \
  --services modresorts-backend-service \
  --region <region>

# List running tasks
aws ecs list-tasks \
  --cluster <cluster-name> \
  --service-name modresorts-backend-service \
  --region <region>

# View task details
aws ecs describe-tasks \
  --cluster <cluster-name> \
  --tasks <task-id> \
  --region <region>
```

### Step 5: Access the Application
```bash
# If using Load Balancer:
# Get ALB DNS name from deployment output
# Access: http://<alb-dns-name>
# Health: http://<alb-dns-name>/health

# If not using Load Balancer:
# Get task public IP
aws ecs describe-tasks \
  --cluster <cluster-name> \
  --tasks <task-id> \
  --region <region> \
  --query 'tasks[0].attachments[0].details[?name==`networkInterfaceId`].value' \
  --output text

# Access: http://<task-public-ip>:8080
```

---

## Configuration Management

### Environment Variables

The application supports the following environment variables:

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `JAVA_OPTS` | JVM options | `-Xmx512m -Xms256m` | No |
| `TZ` | Timezone | `UTC` | No |
| `DB_HOST` | Database host | `localhost` | Yes |
| `DB_PORT` | Database port | `5432` | Yes |
| `DB_NAME` | Database name | `modresorts` | Yes |
| `DB_USER` | Database user | `admin` | Yes |
| `DB_PASSWORD` | Database password | - | Yes |

### JVM Tuning

For containerized Java applications, consider these JVM options:

```bash
# Basic memory settings
JAVA_OPTS="-Xmx512m -Xms256m"

# Container-aware settings
JAVA_OPTS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0"

# Garbage collection tuning
JAVA_OPTS="-XX:+UseG1GC -XX:MaxGCPauseMillis=200"

# Debugging (development only)
JAVA_OPTS="-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=*:5005"
```

### ECS Task Definition Configuration

**CPU and Memory Combinations (Fargate):**

| CPU (vCPU) | Memory (MB) |
|------------|-------------|
| 256 (.25)  | 512, 1024, 2048 |
| 512 (.5)   | 1024, 2048, 3072, 4096 |
| 1024 (1)   | 2048-8192 (increments of 1024) |
| 2048 (2)   | 4096-16384 (increments of 1024) |
| 4096 (4)   | 8192-30720 (increments of 1024) |

**Default Configuration:**
- CPU: 512 (.5 vCPU)
- Memory: 1024 MB

To modify, edit `ecs/task-definition.json`:
```json
{
  "cpu": "1024",
  "memory": "2048"
}
```

---

## Troubleshooting

### Common Issues

#### 1. Container Fails to Start
**Symptoms:** Task stops immediately after starting

**Solutions:**
```bash
# Check CloudWatch logs
aws logs tail /ecs/modresorts-backend --follow --region <region>

# Check task stopped reason
aws ecs describe-tasks \
  --cluster <cluster-name> \
  --tasks <task-id> \
  --region <region> \
  --query 'tasks[0].stoppedReason'

# Common causes:
# - Invalid environment variables
# - Insufficient memory
# - Application startup errors
```

#### 2. Health Check Failures
**Symptoms:** Tasks are marked unhealthy and replaced

**Solutions:**
```bash
# Test health endpoint locally
curl http://localhost:8080/health

# Check health check configuration in task definition
# Increase startPeriod if application takes longer to start
# Default: 60 seconds

# Verify security group allows traffic on port 8080
```

#### 3. Cannot Pull Image from ECR
**Symptoms:** "CannotPullContainerError"

**Solutions:**
```bash
# Verify ECR repository exists
aws ecr describe-repositories --region <region>

# Verify task execution role has ECR permissions
aws iam get-role --role-name ecsTaskExecutionRole

# Verify image URI is correct
# Format: <account-id>.dkr.ecr.<region>.amazonaws.com/<repo>:<tag>
```

#### 4. Out of Memory Errors
**Symptoms:** Task stops with exit code 137

**Solutions:**
```bash
# Increase task memory in task definition
# Adjust JVM heap size
JAVA_OPTS="-Xmx768m -Xms384m"

# Monitor memory usage
aws cloudwatch get-metric-statistics \
  --namespace AWS/ECS \
  --metric-name MemoryUtilization \
  --dimensions Name=ServiceName,Value=modresorts-backend-service \
  --start-time 2024-01-01T00:00:00Z \
  --end-time 2024-01-01T23:59:59Z \
  --period 300 \
  --statistics Average
```

#### 5. Network Connectivity Issues
**Symptoms:** Cannot connect to database or external services

**Solutions:**
```bash
# Verify security group allows outbound traffic
# Verify subnets have internet gateway (for public access)
# Verify NAT gateway (for private subnets)

# Test connectivity from task
aws ecs execute-command \
  --cluster <cluster-name> \
  --task <task-id> \
  --container modresorts-backend \
  --interactive \
  --command "/bin/bash"
```

### Debugging Commands

```bash
# View service events
aws ecs describe-services \
  --cluster <cluster-name> \
  --services modresorts-backend-service \
  --region <region> \
  --query 'services[0].events[0:10]'

# View task logs
aws logs tail /ecs/modresorts-backend --follow --region <region>

# Describe task
aws ecs describe-tasks \
  --cluster <cluster-name> \
  --tasks <task-id> \
  --region <region>

# List all tasks
aws ecs list-tasks \
  --cluster <cluster-name> \
  --service-name modresorts-backend-service \
  --region <region>
```

---

## Security Considerations

### 1. Container Security
- **Non-root user:** Application runs as `appuser` (UID 1000)
- **Read-only root filesystem:** Consider enabling in task definition
- **No privileged mode:** Never use privileged containers

### 2. Network Security
- **Security groups:** Restrict inbound traffic to necessary ports only
- **Private subnets:** Deploy tasks in private subnets with NAT gateway
- **VPC endpoints:** Use VPC endpoints for AWS services (ECR, CloudWatch)

### 3. Secrets Management
- **Never hardcode secrets** in Dockerfile or task definition
- **Use AWS Secrets Manager** for sensitive data:

```json
{
  "secrets": [
    {
      "name": "DB_PASSWORD",
      "valueFrom": "arn:aws:secretsmanager:region:account-id:secret:db-password"
    }
  ]
}
```

### 4. IAM Permissions
- **Principle of least privilege:** Grant only necessary permissions
- **Task role:** Use for application-level AWS API calls
- **Execution role:** Use for ECS infrastructure operations

### 5. Image Security
- **Scan images:** Use ECR image scanning
```bash
aws ecr start-image-scan \
  --repository-name modresorts-backend \
  --image-id imageTag=latest \
  --region <region>
```

- **Use official base images:** Eclipse Temurin, Tomcat
- **Keep images updated:** Regularly rebuild with latest base images

---

## Monitoring and Logging

### CloudWatch Logs

**Log Group:** `/ecs/modresorts-backend`

**View logs:**
```bash
# Tail logs
aws logs tail /ecs/modresorts-backend --follow --region <region>

# Filter logs
aws logs filter-log-events \
  --log-group-name /ecs/modresorts-backend \
  --filter-pattern "ERROR" \
  --region <region>

# Export logs
aws logs create-export-task \
  --log-group-name /ecs/modresorts-backend \
  --from 1609459200000 \
  --to 1609545600000 \
  --destination s3-bucket-name \
  --region <region>
```

### CloudWatch Metrics

**Key metrics to monitor:**
- CPU Utilization
- Memory Utilization
- Network In/Out
- Task Count

**Create alarms:**
```bash
# High CPU alarm
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
  --dimensions Name=ServiceName,Value=modresorts-backend-service

# High memory alarm
aws cloudwatch put-metric-alarm \
  --alarm-name modresorts-high-memory \
  --alarm-description "Alert when memory exceeds 80%" \
  --metric-name MemoryUtilization \
  --namespace AWS/ECS \
  --statistic Average \
  --period 300 \
  --threshold 80 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 2 \
  --dimensions Name=ServiceName,Value=modresorts-backend-service
```

### Application Monitoring

**Health Check Endpoint:**
```bash
# Check application health
curl http://<alb-dns-name>/health

# Expected response:
{
  "status": "UP",
  "application": "ModResorts",
  "version": "2.0.0",
  "timestamp": 1234567890
}
```

### ECS Service Auto Scaling

**Configure auto scaling:**
```bash
# Register scalable target
aws application-autoscaling register-scalable-target \
  --service-namespace ecs \
  --resource-id service/<cluster-name>/modresorts-backend-service \
  --scalable-dimension ecs:service:DesiredCount \
  --min-capacity 2 \
  --max-capacity 10

# Create scaling policy (CPU-based)
aws application-autoscaling put-scaling-policy \
  --service-namespace ecs \
  --resource-id service/<cluster-name>/modresorts-backend-service \
  --scalable-dimension ecs:service:DesiredCount \
  --policy-name cpu-scaling-policy \
  --policy-type TargetTrackingScaling \
  --target-tracking-scaling-policy-configuration file://scaling-policy.json
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

---

## Additional Resources

### AWS Documentation
- [ECS Fargate Documentation](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/AWS_Fargate.html)
- [ECS Task Definitions](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definitions.html)
- [ECR User Guide](https://docs.aws.amazon.com/AmazonECR/latest/userguide/what-is-ecr.html)

### Docker Documentation
- [Dockerfile Best Practices](https://docs.docker.com/develop/develop-images/dockerfile_best-practices/)
- [Docker Compose Documentation](https://docs.docker.com/compose/)

### Java in Containers
- [Java SE Support for Docker CPU and Memory Limits](https://blogs.oracle.com/java/post/java-se-support-for-docker-cpu-and-memory-limits)
- [Best Practices for Java Apps in Containers](https://developers.redhat.com/blog/2017/03/14/java-inside-docker)

---

## Support and Maintenance

### Updating the Application

1. **Build new image:**
```bash
./scripts/build-push.sh
```

2. **Deploy update:**
```bash
./scripts/deploy-image.sh
# The script will automatically update the service with the new task definition
```

3. **Monitor deployment:**
```bash
aws ecs describe-services \
  --cluster <cluster-name> \
  --services modresorts-backend-service \
  --region <region>
```

### Rollback

```bash
# List task definition revisions
aws ecs list-task-definitions \
  --family-prefix modresorts-backend-task \
  --region <region>

# Update service to previous revision
aws ecs update-service \
  --cluster <cluster-name> \
  --service modresorts-backend-service \
  --task-definition modresorts-backend-task:<revision> \
  --region <region>
```

### Cleanup

```bash
# Delete service
aws ecs delete-service \
  --cluster <cluster-name> \
  --service modresorts-backend-service \
  --force \
  --region <region>

# Delete cluster
aws ecs delete-cluster \
  --cluster <cluster-name> \
  --region <region>

# Delete load balancer
aws elbv2 delete-load-balancer \
  --load-balancer-arn <alb-arn>

# Delete target group
aws elbv2 delete-target-group \
  --target-group-arn <target-group-arn>

# Delete ECR repository
aws ecr delete-repository \
  --repository-name modresorts-backend \
  --force \
  --region <region>
```

---

## Conclusion

This deployment guide provides comprehensive instructions for containerizing and deploying the ModResorts Backend application to AWS ECS Fargate. Follow the steps carefully and refer to the troubleshooting section for common issues.

For additional support, consult the AWS documentation or contact your DevOps team.
