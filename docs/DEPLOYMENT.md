# ModResorts - AWS ECS Fargate Deployment Guide

## Table of Contents
1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Project Architecture](#project-architecture)
4. [Local Development Setup](#local-development-setup)
5. [Docker Containerization](#docker-containerization)
6. [AWS ECS Fargate Prerequisites](#aws-ecs-fargate-prerequisites)
7. [ECS Fargate Setup](#ecs-fargate-setup)
8. [Building and Pushing Images](#building-and-pushing-images)
9. [ECS Task Definition](#ecs-task-definition)
10. [ECS Service Configuration](#ecs-service-configuration)
11. [Deployment Walkthrough](#deployment-walkthrough)
12. [Configuration Management](#configuration-management)
13. [Monitoring and Logging](#monitoring-and-logging)
14. [Troubleshooting](#troubleshooting)
15. [Scaling and Management](#scaling-and-management)
16. [Security Considerations](#security-considerations)

---

## Overview

ModResorts is a Java 8 Spring Boot application containerized for deployment on AWS ECS Fargate. This guide provides comprehensive instructions for building, deploying, and managing the application in a containerized environment.

**Technology Stack:**
- Java 8
- Spring Boot 2.7.14
- Maven 3.9.4
- Docker
- AWS ECS Fargate
- AWS ECR (Elastic Container Registry)
- AWS CloudWatch (Logging)

**Key Features:**
- Multi-stage Docker build for optimized image size
- Spring Boot Actuator health checks at `/actuator/health`
- Externalized configuration for databases and Redis
- Production-ready JVM tuning for containers
- AWS ECS Fargate deployment with auto-scaling capabilities

---

## Prerequisites

### Required Software
- **Docker Desktop** (20.10+): [Install Docker](https://docs.docker.com/get-docker/)
- **AWS CLI** (2.x): [Install AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
- **Java 8 JDK** (for local development): [Install OpenJDK 8](https://adoptium.net/)
- **Maven 3.6+** (for local builds): [Install Maven](https://maven.apache.org/install.html)
- **Git**: [Install Git](https://git-scm.com/downloads)

### AWS Account Requirements
- Active AWS account with appropriate permissions
- IAM user with permissions for:
  - ECS (create/manage clusters, services, tasks)
  - ECR (create repositories, push images)
  - CloudWatch Logs (create log groups)
  - VPC (manage networking)
  - IAM (create/manage roles)
  - Application Load Balancer (optional)

### AWS CLI Configuration
```bash
# Configure AWS CLI with your credentials
aws configure

# Verify configuration
aws sts get-caller-identity
```

---

## Project Architecture

### Application Structure
```
modresorts/
├── src/
│   ├── main/
│   │   ├── java/
│   │   │   └── com/acme/modres/
│   │   │       ├── ModResortsApplication.java  # Spring Boot main class
│   │   │       ├── WelcomeServlet.java
│   │   │       ├── mbean/                      # Business logic
│   │   │       ├── security/                   # Security components
│   │   │       └── util/                       # Utilities
│   │   └── resources/
│   │       └── application.properties          # Configuration
│   └── test/
├── WebContent/                                  # Web resources
├── pom.xml                                      # Maven configuration
├── Dockerfile                                   # Multi-stage Docker build
├── docker-compose.yml                           # Local development
├── .dockerignore                                # Docker build exclusions
├── scripts/
│   ├── build-push.sh                           # Build & push (Linux/macOS)
│   ├── build-push.bat                          # Build & push (Windows)
│   ├── deploy-image.sh                         # ECS deployment (Linux/macOS)
│   └── deploy-image.bat                        # ECS deployment (Windows)
├── ecs/
│   ├── task-definition.json                    # ECS task configuration
│   └── service-definition.json                 # ECS service configuration
└── docs/
    └── DEPLOYMENT.md                           # This file
```

### Container Architecture
```
┌─────────────────────────────────────────────┐
│         AWS ECS Fargate Cluster             │
│                                             │
│  ┌───────────────────────────────────────┐ │
│  │     Application Load Balancer         │ │
│  │         (Port 80 → 8080)              │ │
│  └───────────────┬───────────────────────┘ │
│                  │                          │
│  ┌───────────────▼───────────────────────┐ │
│  │      ECS Service (modresorts)         │ │
│  │      Desired Count: 2 tasks           │ │
│  └───────────────┬───────────────────────┘ │
│                  │                          │
│  ┌───────────────▼───────────────────────┐ │
│  │   Task 1          │      Task 2       │ │
│  │  ┌─────────────┐  │  ┌─────────────┐ │ │
│  │  │ ModResorts  │  │  │ ModResorts  │ │ │
│  │  │ Container   │  │  │ Container   │ │ │
│  │  │ Port: 8080  │  │  │ Port: 8080  │ │ │
│  │  └─────────────┘  │  └─────────────┘ │ │
│  └───────────────────────────────────────┘ │
│                                             │
│  ┌───────────────────────────────────────┐ │
│  │      CloudWatch Logs                  │ │
│  │      /ecs/modresorts                  │ │
│  └───────────────────────────────────────┘ │
└─────────────────────────────────────────────┘
         │                    │
         ▼                    ▼
   ┌──────────┐        ┌──────────┐
   │ RDS      │        │ ElastiCache│
   │ Database │        │ Redis     │
   └──────────┘        └──────────┘
```

---

## Local Development Setup

### 1. Clone the Repository
```bash
git clone <repository-url>
cd fullcomp
```

### 2. Build with Maven
```bash
# Clean and build
mvn clean package -DskipTests

# The WAR file will be in target/modresorts-2.0.0.war
```

### 3. Run Locally (Spring Boot)
```bash
# Run with default configuration
java -jar target/modresorts-2.0.0.war

# Run with custom port
SERVER_PORT=8081 java -jar target/modresorts-2.0.0.war

# Access the application
curl http://localhost:8080/actuator/health
```

### 4. Local Development with Docker Compose
```bash
# Build and start the application
docker-compose up --build

# Access the application
curl http://localhost:8080/actuator/health

# View logs
docker-compose logs -f

# Stop the application
docker-compose down
```

---

## Docker Containerization

### Dockerfile Overview

The Dockerfile uses a **multi-stage build** approach:

**Stage 1: Builder**
- Base image: `maven:3.9.4-eclipse-temurin-8`
- Downloads dependencies (cached layer)
- Builds the WAR file

**Stage 2: Runtime**
- Base image: `eclipse-temurin:8-jdk` (explicitly specified)
- Copies only the WAR file from builder
- Creates non-root user for security
- Configures JVM options for containers
- Exposes port 8080

### Key Dockerfile Features

1. **Dependency Caching**: Maven dependencies are downloaded in a separate layer
2. **Security**: Runs as non-root user `appuser`
3. **JVM Optimization**: Container-aware JVM settings
4. **Health Checks**: Handled by ECS service (no curl/wget in image)
5. **Minimal Runtime**: Only includes necessary runtime components

### Build Docker Image Locally
```bash
# Build the image
docker build -t modresorts:latest .

# Run the container
docker run -p 8080:8080 \
  -e JAVA_OPTS="-Xmx512m -Xms256m" \
  -e SPRING_PROFILES_ACTIVE=docker \
  modresorts:latest

# Test the application
curl http://localhost:8080/actuator/health
```

---

## AWS ECS Fargate Prerequisites

### 1. IAM Roles

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

# Create the role
aws iam create-role \
  --role-name ecsTaskExecutionRole \
  --assume-role-policy-document file://ecs-task-execution-trust-policy.json

# Attach AWS managed policy
aws iam attach-role-policy \
  --role-name ecsTaskExecutionRole \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy
```

#### ECS Task Role (Optional)
This role grants permissions to the application itself (e.g., access to S3, DynamoDB).

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

### 2. VPC and Networking

#### Create VPC (if needed)
```bash
# Create VPC
VPC_ID=$(aws ec2 create-vpc \
  --cidr-block 10.0.0.0/16 \
  --query 'Vpc.VpcId' \
  --output text)

# Enable DNS hostnames
aws ec2 modify-vpc-attribute \
  --vpc-id $VPC_ID \
  --enable-dns-hostnames

# Create Internet Gateway
IGW_ID=$(aws ec2 create-internet-gateway \
  --query 'InternetGateway.InternetGatewayId' \
  --output text)

# Attach Internet Gateway to VPC
aws ec2 attach-internet-gateway \
  --vpc-id $VPC_ID \
  --internet-gateway-id $IGW_ID
```

#### Create Subnets
```bash
# Create public subnet 1 (us-east-1a)
SUBNET_1=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block 10.0.1.0/24 \
  --availability-zone us-east-1a \
  --query 'Subnet.SubnetId' \
  --output text)

# Create public subnet 2 (us-east-1b)
SUBNET_2=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block 10.0.2.0/24 \
  --availability-zone us-east-1b \
  --query 'Subnet.SubnetId' \
  --output text)

# Enable auto-assign public IP
aws ec2 modify-subnet-attribute \
  --subnet-id $SUBNET_1 \
  --map-public-ip-on-launch

aws ec2 modify-subnet-attribute \
  --subnet-id $SUBNET_2 \
  --map-public-ip-on-launch
```

#### Create Route Table
```bash
# Create route table
ROUTE_TABLE_ID=$(aws ec2 create-route-table \
  --vpc-id $VPC_ID \
  --query 'RouteTable.RouteTableId' \
  --output text)

# Add route to Internet Gateway
aws ec2 create-route \
  --route-table-id $ROUTE_TABLE_ID \
  --destination-cidr-block 0.0.0.0/0 \
  --gateway-id $IGW_ID

# Associate subnets with route table
aws ec2 associate-route-table \
  --subnet-id $SUBNET_1 \
  --route-table-id $ROUTE_TABLE_ID

aws ec2 associate-route-table \
  --subnet-id $SUBNET_2 \
  --route-table-id $ROUTE_TABLE_ID
```

#### Create Security Group
```bash
# Create security group
SG_ID=$(aws ec2 create-security-group \
  --group-name modresorts-sg \
  --description "Security group for ModResorts ECS tasks" \
  --vpc-id $VPC_ID \
  --query 'GroupId' \
  --output text)

# Allow inbound HTTP (port 80) from anywhere
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp \
  --port 80 \
  --cidr 0.0.0.0/0

# Allow inbound traffic on port 8080 from within VPC
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp \
  --port 8080 \
  --cidr 10.0.0.0/16

# Allow all outbound traffic (default)
```

### 3. CloudWatch Log Group
```bash
# Create log group for ECS tasks
aws logs create-log-group \
  --log-group-name /ecs/modresorts \
  --region us-east-1

# Set retention policy (optional, 7 days)
aws logs put-retention-policy \
  --log-group-name /ecs/modresorts \
  --retention-in-days 7 \
  --region us-east-1
```

---

## ECS Fargate Setup

### Understanding ECS Fargate

**AWS Fargate** is a serverless compute engine for containers that:
- Eliminates the need to manage EC2 instances
- Automatically scales based on demand
- Charges only for resources used by containers
- Provides built-in security and isolation

### ECS Fargate Components

1. **Cluster**: Logical grouping of tasks and services
2. **Task Definition**: Blueprint for your application (like a Dockerfile for ECS)
3. **Service**: Maintains desired number of tasks running
4. **Task**: Running instance of a task definition

### Valid Fargate CPU/Memory Combinations

| CPU (vCPU) | Memory (MB) Options |
|------------|---------------------|
| 256 (.25)  | 512, 1024, 2048 |
| 512 (.5)   | 1024, 2048, 3072, 4096 |
| 1024 (1)   | 2048, 3072, 4096, 5120, 6144, 7168, 8192 |
| 2048 (2)   | 4096-16384 (increments of 1024) |
| 4096 (4)   | 8192-30720 (increments of 1024) |

**Default for ModResorts**: CPU: 512, Memory: 1024

---

## Building and Pushing Images

### Option 1: Using build-push.sh (Linux/macOS)

```bash
# Make script executable
chmod +x scripts/build-push.sh

# Run the script
./scripts/build-push.sh

# Follow the prompts:
# 1. Select registry (1=ECR, 2=Docker Hub)
# 2. Enter image tag (default: latest)
# 3. Provide registry credentials
```

### Option 2: Using build-push.bat (Windows)

```cmd
# Run the script
scripts\build-push.bat

# Follow the prompts
```

### Manual Build and Push to ECR

```bash
# Set variables
AWS_REGION=us-east-1
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_REPO=modresorts
IMAGE_TAG=latest

# Create ECR repository (if not exists)
aws ecr create-repository \
  --repository-name $ECR_REPO \
  --region $AWS_REGION

# Authenticate Docker to ECR
aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin \
  $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

# Build the image
docker build -t $ECR_REPO:$IMAGE_TAG .

# Tag the image
docker tag $ECR_REPO:$IMAGE_TAG \
  $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPO:$IMAGE_TAG

# Push to ECR
docker push \
  $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPO:$IMAGE_TAG
```

---

## ECS Task Definition

### Task Definition Overview

The task definition (`ecs/task-definition.json`) defines:
- Container image and configuration
- CPU and memory allocation
- Environment variables
- Logging configuration
- IAM roles
- Network mode

### Key Configuration

```json
{
  "family": "modresorts-task",
  "networkMode": "awsvpc",              // Required for Fargate
  "requiresCompatibilities": ["FARGATE"], // Fargate launch type
  "cpu": "512",                          // 0.5 vCPU
  "memory": "1024",                      // 1 GB
  "executionRoleArn": "...",             // For ECR and CloudWatch
  "taskRoleArn": "...",                  // For application permissions
  "containerDefinitions": [...]
}
```

### Container Definition

```json
{
  "name": "modresorts",
  "image": "{{IMAGE_URI}}",              // Replaced during deployment
  "essential": true,
  "portMappings": [
    {
      "containerPort": 8080,
      "protocol": "tcp"
    }
  ],
  "environment": [
    {"name": "JAVA_OPTS", "value": "-Xmx512m -Xms256m ..."},
    {"name": "SPRING_PROFILES_ACTIVE", "value": "docker"},
    {"name": "DB_URL", "value": "{{DB_URL}}"},
    ...
  ],
  "logConfiguration": {
    "logDriver": "awslogs",
    "options": {
      "awslogs-group": "/ecs/modresorts",
      "awslogs-region": "{{AWS_REGION}}",
      "awslogs-stream-prefix": "ecs"
    }
  }
}
```

### Environment Variables

The task definition includes placeholders for:
- `{{IMAGE_URI}}`: ECR image URI
- `{{AWS_REGION}}`: AWS region
- `{{ACCOUNT_ID}}`: AWS account ID
- `{{DB_URL}}`: Database connection string
- `{{DB_USERNAME}}`: Database username
- `{{DB_PASSWORD}}`: Database password
- `{{REDIS_HOST}}`: Redis host
- `{{REDIS_PORT}}`: Redis port
- `{{REDIS_PASSWORD}}`: Redis password

These are replaced during deployment by the `deploy-image.sh` script.

---

## ECS Service Configuration

### Service Definition Overview

The service definition (`ecs/service-definition.json`) defines:
- Desired number of tasks
- Load balancer configuration
- Network configuration
- Deployment strategy
- Auto-scaling policies

### Key Configuration

```json
{
  "serviceName": "modresorts-service",
  "cluster": "{{CLUSTER_NAME}}",
  "taskDefinition": "modresorts-task",
  "desiredCount": 2,                     // Number of tasks
  "launchType": "FARGATE",
  "networkConfiguration": {
    "awsvpcConfiguration": {
      "subnets": ["{{SUBNET_1}}", "{{SUBNET_2}}"],
      "securityGroups": ["{{SECURITY_GROUP}}"],
      "assignPublicIp": "ENABLED"        // For internet access
    }
  },
  "deploymentConfiguration": {
    "maximumPercent": 200,               // Rolling update strategy
    "minimumHealthyPercent": 50
  }
}
```

### Load Balancer Configuration

If using an Application Load Balancer:

```json
{
  "loadBalancers": [
    {
      "targetGroupArn": "{{TARGET_GROUP_ARN}}",
      "containerName": "modresorts",
      "containerPort": 8080
    }
  ],
  "healthCheckGracePeriodSeconds": 300   // Time for app to start
}
```

### Deployment Strategy

- **maximumPercent: 200**: Allows up to 2x desired tasks during deployment
- **minimumHealthyPercent: 50**: Ensures at least 50% of tasks are healthy
- **Circuit Breaker**: Automatically rolls back failed deployments

---

## Deployment Walkthrough

### Step-by-Step Deployment

#### 1. Build and Push Image

```bash
# Linux/macOS
./scripts/build-push.sh

# Windows
scripts\build-push.bat
```

**What happens:**
- Builds Docker image with Maven
- Tags image appropriately
- Authenticates with ECR or Docker Hub
- Pushes image to registry
- Creates ECR repository if needed

#### 2. Deploy to ECS Fargate

```bash
# Linux/macOS
./scripts/deploy-image.sh

# Windows
scripts\deploy-image.bat
```

**What happens:**
1. Prompts for AWS configuration (region, cluster)
2. Retrieves AWS account ID
3. Creates/verifies ECS cluster
4. Prompts for network configuration (VPC, subnets, security group)
5. Prompts for image URI
6. Prompts for database and Redis configuration
7. Asks if load balancer is needed
8. If yes: Creates ALB, target group, and listener
9. Creates CloudWatch log group
10. Replaces placeholders in task definition
11. Registers task definition with ECS
12. Creates or updates ECS service
13. Waits for service to become stable
14. Displays deployment information

#### 3. Verify Deployment

```bash
# Check service status
aws ecs describe-services \
  --cluster modresorts-cluster \
  --services modresorts-service \
  --region us-east-1

# List running tasks
aws ecs list-tasks \
  --cluster modresorts-cluster \
  --service-name modresorts-service \
  --region us-east-1

# View task details
aws ecs describe-tasks \
  --cluster modresorts-cluster \
  --tasks <task-id> \
  --region us-east-1
```

#### 4. Access the Application

**With Load Balancer:**
```bash
# Get ALB DNS name
aws elbv2 describe-load-balancers \
  --names modresorts-alb \
  --region us-east-1 \
  --query 'LoadBalancers[0].DNSName' \
  --output text

# Access application
curl http://<alb-dns-name>/actuator/health
```

**Without Load Balancer:**
```bash
# Get task public IP
aws ecs describe-tasks \
  --cluster modresorts-cluster \
  --tasks <task-id> \
  --region us-east-1 \
  --query 'tasks[0].attachments[0].details[?name==`networkInterfaceId`].value' \
  --output text

# Get ENI public IP
aws ec2 describe-network-interfaces \
  --network-interface-ids <eni-id> \
  --query 'NetworkInterfaces[0].Association.PublicIp' \
  --output text

# Access application
curl http://<public-ip>:8080/actuator/health
```

---

## Configuration Management

### Environment Variables

The application uses environment variables for configuration:

| Variable | Description | Default |
|----------|-------------|---------|
| `JAVA_OPTS` | JVM options | `-Xmx512m -Xms256m ...` |
| `SPRING_PROFILES_ACTIVE` | Spring profile | `docker` |
| `SERVER_PORT` | Application port | `8080` |
| `DB_URL` | Database URL | `jdbc:h2:mem:testdb` |
| `DB_USERNAME` | Database username | `sa` |
| `DB_PASSWORD` | Database password | (empty) |
| `DB_DRIVER` | JDBC driver class | `org.h2.Driver` |
| `REDIS_HOST` | Redis host | `localhost` |
| `REDIS_PORT` | Redis port | `6379` |
| `REDIS_PASSWORD` | Redis password | (empty) |

### Updating Configuration

#### Option 1: Update Task Definition

```bash
# Edit ecs/task-definition.json
# Update environment variables

# Register new task definition
aws ecs register-task-definition \
  --cli-input-json file://ecs/task-definition.json \
  --region us-east-1

# Update service to use new task definition
aws ecs update-service \
  --cluster modresorts-cluster \
  --service modresorts-service \
  --task-definition modresorts-task:2 \
  --region us-east-1
```

#### Option 2: Use AWS Systems Manager Parameter Store

```bash
# Store secrets in Parameter Store
aws ssm put-parameter \
  --name /modresorts/db/password \
  --value "your-password" \
  --type SecureString \
  --region us-east-1

# Update task definition to use secrets
# Add to containerDefinitions:
"secrets": [
  {
    "name": "DB_PASSWORD",
    "valueFrom": "/modresorts/db/password"
  }
]
```

---

## Monitoring and Logging

### CloudWatch Logs

**View Logs:**
```bash
# Tail logs in real-time
aws logs tail /ecs/modresorts --follow --region us-east-1

# View logs for specific time range
aws logs filter-log-events \
  --log-group-name /ecs/modresorts \
  --start-time $(date -d '1 hour ago' +%s)000 \
  --region us-east-1

# Search logs
aws logs filter-log-events \
  --log-group-name /ecs/modresorts \
  --filter-pattern "ERROR" \
  --region us-east-1
```

**CloudWatch Insights Queries:**
```sql
-- Count errors by hour
fields @timestamp, @message
| filter @message like /ERROR/
| stats count() by bin(1h)

-- Find slow requests
fields @timestamp, @message
| filter @message like /duration/
| parse @message /duration=(?<duration>\d+)/
| filter duration > 1000
| sort duration desc
```

### CloudWatch Metrics

**ECS Service Metrics:**
- CPUUtilization
- MemoryUtilization
- TargetResponseTime (with ALB)
- RequestCount (with ALB)
- HealthyHostCount (with ALB)

**View Metrics:**
```bash
# Get CPU utilization
aws cloudwatch get-metric-statistics \
  --namespace AWS/ECS \
  --metric-name CPUUtilization \
  --dimensions Name=ServiceName,Value=modresorts-service Name=ClusterName,Value=modresorts-cluster \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average \
  --region us-east-1
```

### CloudWatch Alarms

**Create CPU Alarm:**
```bash
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
  --dimensions Name=ServiceName,Value=modresorts-service Name=ClusterName,Value=modresorts-cluster \
  --region us-east-1
```

### Application Health Checks

**Spring Boot Actuator Endpoints:**
- `/actuator/health`: Overall health status
- `/actuator/info`: Application information
- `/actuator/metrics`: Application metrics

**Test Health Endpoint:**
```bash
# With ALB
curl http://<alb-dns>/actuator/health

# Direct to task
curl http://<task-ip>:8080/actuator/health

# Expected response
{
  "status": "UP"
}
```

---

## Troubleshooting

### Common Issues and Solutions

#### 1. Task Fails to Start

**Symptoms:**
- Tasks start and immediately stop
- "Essential container exited" error

**Diagnosis:**
```bash
# Get stopped task details
aws ecs describe-tasks \
  --cluster modresorts-cluster \
  --tasks <task-id> \
  --region us-east-1

# Check CloudWatch logs
aws logs tail /ecs/modresorts --since 10m --region us-east-1
```

**Common Causes:**
- Invalid image URI
- Missing IAM permissions
- Application startup failure
- Invalid environment variables

**Solutions:**
- Verify image exists in ECR
- Check executionRoleArn has ECR and CloudWatch permissions
- Review application logs for startup errors
- Validate environment variable values

#### 2. Cannot Pull Image from ECR

**Symptoms:**
- "CannotPullContainerError"
- "Image not found"

**Diagnosis:**
```bash
# Verify image exists
aws ecr describe-images \
  --repository-name modresorts \
  --region us-east-1

# Check execution role permissions
aws iam get-role-policy \
  --role-name ecsTaskExecutionRole \
  --policy-name AmazonECSTaskExecutionRolePolicy
```

**Solutions:**
- Ensure image was pushed successfully
- Verify executionRoleArn has `ecr:GetAuthorizationToken`, `ecr:BatchCheckLayerAvailability`, `ecr:GetDownloadUrlForLayer`, `ecr:BatchGetImage`
- Check image URI format: `<account-id>.dkr.ecr.<region>.amazonaws.com/<repo>:<tag>`

#### 3. Service Fails Health Checks

**Symptoms:**
- Tasks continuously restart
- "Target.FailedHealthChecks" in ALB

**Diagnosis:**
```bash
# Check target health
aws elbv2 describe-target-health \
  --target-group-arn <target-group-arn> \
  --region us-east-1

# Test health endpoint directly
curl http://<task-ip>:8080/actuator/health
```

**Common Causes:**
- Application not listening on correct port
- Health endpoint not accessible
- Security group blocking traffic
- Application startup time exceeds grace period

**Solutions:**
- Verify `SERVER_PORT` environment variable
- Ensure `/actuator/health` endpoint is enabled
- Check security group allows inbound traffic on port 8080
- Increase `healthCheckGracePeriodSeconds` in service definition

#### 4. Out of Memory Errors

**Symptoms:**
- Tasks killed with exit code 137
- "OutOfMemoryError" in logs

**Diagnosis:**
```bash
# Check memory utilization
aws cloudwatch get-metric-statistics \
  --namespace AWS/ECS \
  --metric-name MemoryUtilization \
  --dimensions Name=ServiceName,Value=modresorts-service Name=ClusterName,Value=modresorts-cluster \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Maximum \
  --region us-east-1
```

**Solutions:**
- Increase task memory in task definition (e.g., 1024 → 2048)
- Adjust JVM heap size: `-Xmx` should be ~75% of container memory
- Review application for memory leaks
- Enable JVM garbage collection logging

#### 5. Network Connectivity Issues

**Symptoms:**
- Cannot connect to database or Redis
- "Connection refused" errors

**Diagnosis:**
```bash
# Check security group rules
aws ec2 describe-security-groups \
  --group-ids <security-group-id> \
  --region us-east-1

# Test connectivity from task
aws ecs execute-command \
  --cluster modresorts-cluster \
  --task <task-id> \
  --container modresorts \
  --interactive \
  --command "/bin/sh"
```

**Solutions:**
- Verify security group allows outbound traffic
- Ensure database/Redis security groups allow inbound from ECS security group
- Check VPC routing and NAT gateway configuration
- Verify DNS resolution for external services

#### 6. Deployment Stuck

**Symptoms:**
- Service update never completes
- Tasks in PENDING state

**Diagnosis:**
```bash
# Check service events
aws ecs describe-services \
  --cluster modresorts-cluster \
  --services modresorts-service \
  --region us-east-1 \
  --query 'services[0].events[0:10]'
```

**Common Causes:**
- Insufficient subnet IP addresses
- Service quota limits reached
- Invalid task definition

**Solutions:**
- Use larger subnet CIDR blocks
- Request service quota increase
- Validate task definition JSON
- Check for deployment circuit breaker events

---

## Scaling and Management

### Manual Scaling

**Update Desired Count:**
```bash
# Scale to 4 tasks
aws ecs update-service \
  --cluster modresorts-cluster \
  --service modresorts-service \
  --desired-count 4 \
  --region us-east-1
```

### Auto Scaling

**Create Auto Scaling Target:**
```bash
# Register scalable target
aws application-autoscaling register-scalable-target \
  --service-namespace ecs \
  --resource-id service/modresorts-cluster/modresorts-service \
  --scalable-dimension ecs:service:DesiredCount \
  --min-capacity 2 \
  --max-capacity 10 \
  --region us-east-1
```

**Create Scaling Policy (CPU-based):**
```bash
# Scale based on CPU utilization
aws application-autoscaling put-scaling-policy \
  --service-namespace ecs \
  --resource-id service/modresorts-cluster/modresorts-service \
  --scalable-dimension ecs:service:DesiredCount \
  --policy-name cpu-scaling-policy \
  --policy-type TargetTrackingScaling \
  --target-tracking-scaling-policy-configuration '{
    "TargetValue": 70.0,
    "PredefinedMetricSpecification": {
      "PredefinedMetricType": "ECSServiceAverageCPUUtilization"
    },
    "ScaleInCooldown": 300,
    "ScaleOutCooldown": 60
  }' \
  --region us-east-1
```

**Create Scaling Policy (Request-based):**
```bash
# Scale based on ALB request count
aws application-autoscaling put-scaling-policy \
  --service-namespace ecs \
  --resource-id service/modresorts-cluster/modresorts-service \
  --scalable-dimension ecs:service:DesiredCount \
  --policy-name request-scaling-policy \
  --policy-type TargetTrackingScaling \
  --target-tracking-scaling-policy-configuration '{
    "TargetValue": 1000.0,
    "PredefinedMetricSpecification": {
      "PredefinedMetricType": "ALBRequestCountPerTarget",
      "ResourceLabel": "app/modresorts-alb/<alb-id>/targetgroup/modresorts-tg/<tg-id>"
    },
    "ScaleInCooldown": 300,
    "ScaleOutCooldown": 60
  }' \
  --region us-east-1
```

### Blue/Green Deployments

**Using AWS CodeDeploy:**
```bash
# Create CodeDeploy application
aws deploy create-application \
  --application-name modresorts-app \
  --compute-platform ECS \
  --region us-east-1

# Create deployment group
aws deploy create-deployment-group \
  --application-name modresorts-app \
  --deployment-group-name modresorts-dg \
  --service-role-arn arn:aws:iam::<account-id>:role/CodeDeployServiceRole \
  --ecs-services clusterName=modresorts-cluster,serviceName=modresorts-service \
  --load-balancer-info targetGroupPairInfoList=[{targetGroups=[{name=modresorts-tg-blue},{name=modresorts-tg-green}],prodTrafficRoute={listenerArns=[arn:aws:elasticloadbalancing:...]}}] \
  --deployment-config-name CodeDeployDefault.ECSAllAtOnce \
  --region us-east-1
```

### Rolling Updates

**Update Task Definition:**
```bash
# Register new task definition version
aws ecs register-task-definition \
  --cli-input-json file://ecs/task-definition.json \
  --region us-east-1

# Update service with new task definition
aws ecs update-service \
  --cluster modresorts-cluster \
  --service modresorts-service \
  --task-definition modresorts-task:3 \
  --force-new-deployment \
  --region us-east-1
```

**Deployment Configuration:**
- **maximumPercent: 200**: Allows 2x tasks during update (e.g., 2 → 4 → 2)
- **minimumHealthyPercent: 50**: Ensures at least 1 task remains healthy

### Rollback

**Rollback to Previous Task Definition:**
```bash
# List task definition revisions
aws ecs list-task-definitions \
  --family-prefix modresorts-task \
  --region us-east-1

# Update service to previous version
aws ecs update-service \
  --cluster modresorts-cluster \
  --service modresorts-service \
  --task-definition modresorts-task:1 \
  --region us-east-1
```

---

## Security Considerations

### 1. Container Security

**Best Practices:**
- ✅ Run as non-root user (implemented in Dockerfile)
- ✅ Use minimal base images (eclipse-temurin JRE)
- ✅ Scan images for vulnerabilities
- ✅ Keep base images updated
- ✅ Don't include secrets in images

**Scan Images:**
```bash
# Scan with AWS ECR
aws ecr start-image-scan \
  --repository-name modresorts \
  --image-id imageTag=latest \
  --region us-east-1

# Get scan results
aws ecr describe-image-scan-findings \
  --repository-name modresorts \
  --image-id imageTag=latest \
  --region us-east-1
```

### 2. Network Security

**Security Group Rules:**
- Restrict inbound traffic to necessary ports only
- Use separate security groups for ALB and ECS tasks
- Allow outbound traffic only to required services

**Example Security Group Configuration:**
```bash
# ECS task security group
# Inbound: Port 8080 from ALB security group only
# Outbound: HTTPS (443) for AWS services, database ports

# ALB security group
# Inbound: Port 80/443 from 0.0.0.0/0
# Outbound: Port 8080 to ECS task security group
```

### 3. Secrets Management

**Use AWS Secrets Manager:**
```bash
# Store database password
aws secretsmanager create-secret \
  --name modresorts/db/password \
  --secret-string "your-secure-password" \
  --region us-east-1

# Update task definition to use secrets
"secrets": [
  {
    "name": "DB_PASSWORD",
    "valueFrom": "arn:aws:secretsmanager:us-east-1:<account-id>:secret:modresorts/db/password"
  }
]

# Grant task execution role permission
aws iam attach-role-policy \
  --role-name ecsTaskExecutionRole \
  --policy-arn arn:aws:iam::aws:policy/SecretsManagerReadWrite
```

### 4. IAM Permissions

**Principle of Least Privilege:**
- Task Execution Role: Only ECR pull and CloudWatch logs
- Task Role: Only permissions needed by application
- Avoid using AWS managed policies in production

**Example Task Role Policy:**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject"
      ],
      "Resource": "arn:aws:s3:::modresorts-bucket/*"
    }
  ]
}
```

### 5. Logging and Auditing

**Enable CloudTrail:**
```bash
# Create trail for ECS API calls
aws cloudtrail create-trail \
  --name modresorts-trail \
  --s3-bucket-name modresorts-cloudtrail-logs \
  --region us-east-1

# Start logging
aws cloudtrail start-logging \
  --name modresorts-trail \
  --region us-east-1
```

**Enable VPC Flow Logs:**
```bash
# Create flow log for VPC
aws ec2 create-flow-logs \
  --resource-type VPC \
  --resource-ids <vpc-id> \
  --traffic-type ALL \
  --log-destination-type cloud-watch-logs \
  --log-group-name /aws/vpc/flowlogs \
  --deliver-logs-permission-arn arn:aws:iam::<account-id>:role/flowlogsRole \
  --region us-east-1
```

### 6. Compliance

**HTTPS/TLS:**
- Use HTTPS listeners on ALB
- Terminate TLS at ALB
- Use AWS Certificate Manager for certificates

**Data Encryption:**
- Enable encryption at rest for EBS volumes (default for Fargate)
- Use encrypted RDS instances
- Enable S3 bucket encryption

---

## Technology-Specific Notes

### Java 8 Considerations

**JVM Tuning for Containers:**
```bash
# Recommended JVM options (already in Dockerfile)
JAVA_OPTS="-Xmx512m -Xms256m \
  -XX:+UseContainerSupport \
  -XX:MaxRAMPercentage=75.0 \
  -XX:+UnlockExperimentalVMOptions \
  -Djava.security.egd=file:/dev/./urandom"
```

**Explanation:**
- `-Xmx512m`: Maximum heap size (adjust based on container memory)
- `-Xms256m`: Initial heap size
- `-XX:+UseContainerSupport`: Respect container memory limits
- `-XX:MaxRAMPercentage=75.0`: Use 75% of container memory for heap
- `-Djava.security.egd=file:/dev/./urandom`: Faster startup (non-blocking entropy)

### Spring Boot Actuator

**Health Check Endpoint:**
- Default: `/actuator/health`
- Returns JSON with application status
- Used by ALB target group health checks

**Customize Health Checks:**
```properties
# application.properties
management.endpoint.health.show-details=always
management.health.defaults.enabled=true

# Add custom health indicators
management.health.db.enabled=true
management.health.redis.enabled=true
```

### Maven Build Optimization

**Dependency Caching:**
- Copy `pom.xml` first
- Run `mvn dependency:go-offline`
- Then copy source code
- Reduces build time on code changes

**Multi-Module Projects:**
- Build from project root
- Copy entire project structure
- Build all modules together

---

## Cost Optimization

### 1. Right-Size Resources

**Monitor and Adjust:**
```bash
# Check average CPU/memory usage
aws cloudwatch get-metric-statistics \
  --namespace AWS/ECS \
  --metric-name CPUUtilization \
  --dimensions Name=ServiceName,Value=modresorts-service Name=ClusterName,Value=modresorts-cluster \
  --start-time $(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 86400 \
  --statistics Average \
  --region us-east-1
```

**Recommendations:**
- If CPU < 30%: Consider reducing CPU allocation
- If Memory < 50%: Consider reducing memory allocation
- Use Fargate Spot for non-critical workloads (up to 70% savings)

### 2. Use Fargate Spot

**Update Service for Spot:**
```bash
aws ecs update-service \
  --cluster modresorts-cluster \
  --service modresorts-service \
  --capacity-provider-strategy \
    capacityProvider=FARGATE_SPOT,weight=1,base=0 \
    capacityProvider=FARGATE,weight=0,base=1 \
  --region us-east-1
```

### 3. Optimize Logging

**Set Log Retention:**
```bash
# Reduce retention to 7 days
aws logs put-retention-policy \
  --log-group-name /ecs/modresorts \
  --retention-in-days 7 \
  --region us-east-1
```

### 4. Schedule Scaling

**Scale Down During Off-Hours:**
```bash
# Create scheduled action to scale down at night
aws application-autoscaling put-scheduled-action \
  --service-namespace ecs \
  --resource-id service/modresorts-cluster/modresorts-service \
  --scalable-dimension ecs:service:DesiredCount \
  --scheduled-action-name scale-down-night \
  --schedule "cron(0 22 * * ? *)" \
  --scalable-target-action MinCapacity=1,MaxCapacity=2 \
  --region us-east-1

# Scale up in the morning
aws application-autoscaling put-scheduled-action \
  --service-namespace ecs \
  --resource-id service/modresorts-cluster/modresorts-service \
  --scalable-dimension ecs:service:DesiredCount \
  --scheduled-action-name scale-up-morning \
  --schedule "cron(0 6 * * ? *)" \
  --scalable-target-action MinCapacity=2,MaxCapacity=10 \
  --region us-east-1
```

---

## Additional Resources

### AWS Documentation
- [ECS Fargate Documentation](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/AWS_Fargate.html)
- [ECS Task Definitions](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definitions.html)
- [ECS Service Auto Scaling](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/service-auto-scaling.html)
- [CloudWatch Logs](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/WhatIsCloudWatchLogs.html)

### Spring Boot Resources
- [Spring Boot Actuator](https://docs.spring.io/spring-boot/docs/current/reference/html/actuator.html)
- [Spring Boot Docker](https://spring.io/guides/gs/spring-boot-docker/)
- [Spring Boot Configuration](https://docs.spring.io/spring-boot/docs/current/reference/html/features.html#features.external-config)

### Docker Resources
- [Docker Best Practices](https://docs.docker.com/develop/dev-best-practices/)
- [Multi-Stage Builds](https://docs.docker.com/build/building/multi-stage/)
- [Docker Security](https://docs.docker.com/engine/security/)

---

## Support and Maintenance

### Regular Maintenance Tasks

**Weekly:**
- Review CloudWatch logs for errors
- Check service health and task status
- Monitor resource utilization

**Monthly:**
- Update base images for security patches
- Review and optimize costs
- Update dependencies in pom.xml
- Scan images for vulnerabilities

**Quarterly:**
- Review and update IAM policies
- Audit security group rules
- Test disaster recovery procedures
- Update documentation

### Getting Help

**AWS Support:**
- AWS Support Console
- AWS Forums
- AWS re:Post

**Application Issues:**
- Check CloudWatch logs
- Review ECS service events
- Test locally with Docker Compose

---

## Conclusion

This deployment guide provides comprehensive instructions for containerizing and deploying the ModResorts application on AWS ECS Fargate. By following these steps, you can achieve:

✅ **Scalable Infrastructure**: Auto-scaling based on demand
✅ **High Availability**: Multi-AZ deployment with load balancing
✅ **Security**: IAM roles, security groups, secrets management
✅ **Observability**: CloudWatch logs and metrics
✅ **Cost Optimization**: Right-sized resources and Fargate Spot

For questions or issues, refer to the troubleshooting section or consult AWS documentation.

**Happy Deploying! 🚀**
