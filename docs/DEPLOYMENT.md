# ModResorts Application - AWS ECS Fargate Deployment Guide

## Table of Contents
1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Project Structure](#project-structure)
4. [Local Development](#local-development)
5. [AWS ECS Fargate Prerequisites](#aws-ecs-fargate-prerequisites)
6. [Building and Pushing Docker Image](#building-and-pushing-docker-image)
7. [ECS Fargate Deployment](#ecs-fargate-deployment)
8. [Configuration Management](#configuration-management)
9. [Monitoring and Logging](#monitoring-and-logging)
10. [Troubleshooting](#troubleshooting)
11. [Security Considerations](#security-considerations)
12. [Scaling and Management](#scaling-and-management)

---

## Overview

ModResorts is a Java-based web application built with Servlets and packaged as a WAR file. This guide provides comprehensive instructions for containerizing and deploying the application to AWS ECS Fargate.

**Application Details:**
- **Technology Stack**: Java 8, Servlet 3.1, Maven
- **Package Type**: WAR (Web Application Archive)
- **Application Server**: Apache Tomcat 9.0
- **Application Port**: 8080
- **Health Check Endpoint**: `/health` and `/actuator/health`
- **Target Platform**: AWS ECS Fargate

---

## Prerequisites

### Required Software

1. **Docker Desktop** (version 20.10 or later)
   - Download: https://www.docker.com/products/docker-desktop
   - Verify installation: `docker --version`

2. **AWS CLI** (version 2.x)
   - Download: https://aws.amazon.com/cli/
   - Verify installation: `aws --version`
   - Configure credentials: `aws configure`

3. **Git** (for version control)
   - Download: https://git-scm.com/downloads
   - Verify installation: `git --version`

4. **Java Development Kit (JDK) 8** (for local development)
   - Download: https://adoptium.net/
   - Verify installation: `java -version`

5. **Maven** (version 3.6 or later)
   - Download: https://maven.apache.org/download.cgi
   - Verify installation: `mvn --version`

### AWS Account Requirements

- Active AWS account with appropriate permissions
- IAM user with permissions for:
  - ECS (Elastic Container Service)
  - ECR (Elastic Container Registry)
  - VPC (Virtual Private Cloud)
  - CloudWatch Logs
  - IAM (for role creation)
  - Elastic Load Balancing (optional)

---

## Project Structure

```
modresorts/
├── src/
│   └── main/
│       ├── java/
│       │   └── com/acme/modres/
│       │       ├── WelcomeServlet.java
│       │       ├── HealthCheckServlet.java
│       │       └── ...
│       └── resources/
├── WebContent/
│   └── WEB-INF/
│       └── web.xml
├── pom.xml
├── Dockerfile
├── docker-compose.yml
├── .dockerignore
├── ecs/
│   ├── task-definition.json
│   └── service-definition.json
├── scripts/
│   ├── build-push.sh
│   ├── build-push.bat
│   ├── deploy-image.sh
│   └── deploy-image.bat
└── docs/
    └── DEPLOYMENT.md
```

---

## Local Development

### Building the Application Locally

1. **Clone the repository:**
   ```bash
   git clone <repository-url>
   cd modresorts
   ```

2. **Build with Maven:**
   ```bash
   mvn clean package
   ```
   
   This creates `target/modresorts-2.0.0.war`

3. **Run locally with Docker Compose:**
   ```bash
   docker-compose up --build
   ```

4. **Access the application:**
   - Application: http://localhost:8080
   - Health Check: http://localhost:8080/health

5. **Stop the application:**
   ```bash
   docker-compose down
   ```

### Testing the Docker Image Locally

```bash
# Build the Docker image
docker build -t modresorts:local .

# Run the container
docker run -d -p 8080:8080 --name modresorts-test modresorts:local

# Check logs
docker logs -f modresorts-test

# Test health endpoint
curl http://localhost:8080/health

# Stop and remove container
docker stop modresorts-test
docker rm modresorts-test
```

---

## AWS ECS Fargate Prerequisites

### 1. VPC and Networking Setup

**Create or identify a VPC with:**
- At least 2 subnets in different Availability Zones
- Internet Gateway attached (for public access)
- Route tables configured for internet access

**Using AWS CLI:**
```bash
# List available VPCs
aws ec2 describe-vpcs --query 'Vpcs[*].[VpcId,CidrBlock,Tags[?Key==`Name`].Value|[0]]' --output table

# List subnets in a VPC
aws ec2 describe-subnets --filters "Name=vpc-id,Values=<vpc-id>" --query 'Subnets[*].[SubnetId,AvailabilityZone,CidrBlock]' --output table
```

### 2. Security Group Configuration

**Create a security group that allows:**
- Inbound: Port 8080 (application port) from ALB or 0.0.0.0/0
- Outbound: All traffic (for pulling images and external connections)

**Using AWS CLI:**
```bash
# Create security group
aws ec2 create-security-group \
  --group-name modresorts-sg \
  --description "Security group for ModResorts ECS tasks" \
  --vpc-id <vpc-id>

# Add inbound rule for port 8080
aws ec2 authorize-security-group-ingress \
  --group-id <security-group-id> \
  --protocol tcp \
  --port 8080 \
  --cidr 0.0.0.0/0
```

### 3. IAM Roles Setup

**ECS Task Execution Role** (required for Fargate):
```json
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
```

Attach managed policy: `AmazonECSTaskExecutionRolePolicy`

**Create using AWS CLI:**
```bash
# Create trust policy file
cat > trust-policy.json << EOF
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
  --assume-role-policy-document file://trust-policy.json

# Attach policy
aws iam attach-role-policy \
  --role-name ecsTaskExecutionRole \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy
```

**ECS Task Role** (optional, for application permissions):
```bash
# Create task role for application-specific permissions
aws iam create-role \
  --role-name ecsTaskRole \
  --assume-role-policy-document file://trust-policy.json

# Attach policies as needed (e.g., S3, DynamoDB access)
```

### 4. CloudWatch Logs Setup

The deployment script automatically creates the log group, but you can create it manually:

```bash
aws logs create-log-group --log-group-name /ecs/modresorts
```

---

## Building and Pushing Docker Image

### Option 1: Using the Build Script (Recommended)

**Linux/macOS:**
```bash
cd modresorts
chmod +x scripts/build-push.sh
./scripts/build-push.sh
```

**Windows:**
```cmd
cd modresorts
scripts\build-push.bat
```

The script will:
1. Prompt for registry type (AWS ECR or Docker Hub)
2. Collect necessary credentials and configuration
3. Build the Docker image
4. Authenticate with the selected registry
5. Push the image to the registry

### Option 2: Manual Build and Push

**For AWS ECR:**

1. **Create ECR repository:**
   ```bash
   aws ecr create-repository --repository-name modresorts --region us-east-1
   ```

2. **Authenticate Docker to ECR:**
   ```bash
   aws ecr get-login-password --region us-east-1 | \
     docker login --username AWS --password-stdin <account-id>.dkr.ecr.us-east-1.amazonaws.com
   ```

3. **Build and tag image:**
   ```bash
   docker build -t modresorts:latest .
   docker tag modresorts:latest <account-id>.dkr.ecr.us-east-1.amazonaws.com/modresorts:latest
   ```

4. **Push to ECR:**
   ```bash
   docker push <account-id>.dkr.ecr.us-east-1.amazonaws.com/modresorts:latest
   ```

**For Docker Hub:**

1. **Login to Docker Hub:**
   ```bash
   docker login
   ```

2. **Build and tag image:**
   ```bash
   docker build -t <username>/modresorts:latest .
   ```

3. **Push to Docker Hub:**
   ```bash
   docker push <username>/modresorts:latest
   ```

---

## ECS Fargate Deployment

### Understanding ECS Fargate Components

**Task Definition:**
- Defines the container configuration
- Specifies CPU, memory, image, ports, environment variables
- Includes logging and health check configuration

**Service:**
- Manages the desired number of task instances
- Handles load balancing and service discovery
- Manages rolling updates and deployments

**Cluster:**
- Logical grouping of tasks and services
- Can contain multiple services

### Deployment Steps

#### Step 1: Deploy Using the Script (Recommended)

**Linux/macOS:**
```bash
chmod +x scripts/deploy-image.sh
./scripts/deploy-image.sh
```

**Windows:**
```cmd
scripts\deploy-image.bat
```

The script will prompt for:
- AWS region
- ECS cluster name
- VPC ID
- Subnet IDs (comma-separated)
- Security group ID
- Docker image URI
- Load balancer configuration (yes/no)

#### Step 2: Manual Deployment (Alternative)

**1. Register Task Definition:**
```bash
# Update placeholders in task-definition.json
sed -i 's|{{IMAGE_URI}}|<your-image-uri>|g' ecs/task-definition.json
sed -i 's|{{AWS_REGION}}|us-east-1|g' ecs/task-definition.json
sed -i 's|{{ACCOUNT_ID}}|<your-account-id>|g' ecs/task-definition.json

# Register task definition
aws ecs register-task-definition \
  --cli-input-json file://ecs/task-definition.json \
  --region us-east-1
```

**2. Create ECS Cluster:**
```bash
aws ecs create-cluster --cluster-name modresorts-cluster --region us-east-1
```

**3. Create or Update Service:**
```bash
# Update placeholders in service-definition.json
sed -i 's|{{CLUSTER_NAME}}|modresorts-cluster|g' ecs/service-definition.json
sed -i 's|{{SUBNET_1}}|<subnet-1-id>|g' ecs/service-definition.json
sed -i 's|{{SUBNET_2}}|<subnet-2-id>|g' ecs/service-definition.json
sed -i 's|{{SECURITY_GROUP}}|<security-group-id>|g' ecs/service-definition.json

# Create service
aws ecs create-service \
  --cli-input-json file://ecs/service-definition.json \
  --region us-east-1
```

**4. Wait for Service Stability:**
```bash
aws ecs wait services-stable \
  --cluster modresorts-cluster \
  --services modresorts-service \
  --region us-east-1
```

### Verifying Deployment

**Check service status:**
```bash
aws ecs describe-services \
  --cluster modresorts-cluster \
  --services modresorts-service \
  --region us-east-1
```

**List running tasks:**
```bash
aws ecs list-tasks \
  --cluster modresorts-cluster \
  --service-name modresorts-service \
  --region us-east-1
```

**Get task details:**
```bash
aws ecs describe-tasks \
  --cluster modresorts-cluster \
  --tasks <task-id> \
  --region us-east-1
```

---

## Configuration Management

### Environment Variables

Environment variables can be configured in the task definition:

```json
"environment": [
  {
    "name": "JAVA_OPTS",
    "value": "-Xmx512m -Xms256m"
  },
  {
    "name": "APP_ENV",
    "value": "production"
  }
]
```

### Secrets Management

For sensitive data, use AWS Secrets Manager or Systems Manager Parameter Store:

```json
"secrets": [
  {
    "name": "DB_PASSWORD",
    "valueFrom": "arn:aws:secretsmanager:region:account-id:secret:db-password"
  }
]
```

### JVM Tuning

The Dockerfile includes optimized JVM settings:
- `-Xmx512m -Xms256m`: Heap size limits
- `-XX:+UseContainerSupport`: Container-aware JVM
- `-XX:MaxRAMPercentage=75.0`: Use 75% of container memory

Adjust these based on your task's memory allocation.

---

## Monitoring and Logging

### CloudWatch Logs

**View logs in real-time:**
```bash
aws logs tail /ecs/modresorts --follow --region us-east-1
```

**View logs for specific task:**
```bash
aws logs tail /ecs/modresorts --follow --filter-pattern "<task-id>" --region us-east-1
```

**Search logs:**
```bash
aws logs filter-log-events \
  --log-group-name /ecs/modresorts \
  --filter-pattern "ERROR" \
  --region us-east-1
```

### CloudWatch Metrics

Monitor ECS metrics in CloudWatch:
- CPU utilization
- Memory utilization
- Network traffic
- Task count

**View metrics:**
```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/ECS \
  --metric-name CPUUtilization \
  --dimensions Name=ServiceName,Value=modresorts-service Name=ClusterName,Value=modresorts-cluster \
  --start-time 2024-01-01T00:00:00Z \
  --end-time 2024-01-01T23:59:59Z \
  --period 3600 \
  --statistics Average \
  --region us-east-1
```

### Application Health Checks

The application provides health check endpoints:
- **Primary**: `http://<alb-dns>/health`
- **Alternative**: `http://<alb-dns>/actuator/health`

Health check response:
```json
{
  "status": "UP",
  "application": "ModResorts",
  "version": "2.0.0"
}
```

---

## Troubleshooting

### Common Issues and Solutions

#### 1. Task Fails to Start

**Symptoms:**
- Tasks transition from PENDING to STOPPED
- No running tasks in the service

**Possible Causes and Solutions:**

**a) Image Pull Errors:**
```bash
# Check task stopped reason
aws ecs describe-tasks --cluster modresorts-cluster --tasks <task-id> --region us-east-1

# Verify ECR permissions
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin <account-id>.dkr.ecr.us-east-1.amazonaws.com

# Check if image exists
aws ecr describe-images --repository-name modresorts --region us-east-1
```

**b) Invalid CPU/Memory Combination:**
- Fargate requires specific CPU/memory combinations
- Valid combinations:
  - CPU: 256 → Memory: 512, 1024, 2048
  - CPU: 512 → Memory: 1024, 2048, 3072, 4096
  - CPU: 1024 → Memory: 2048-8192 (increments of 1024)

**c) IAM Role Issues:**
```bash
# Verify execution role exists
aws iam get-role --role-name ecsTaskExecutionRole

# Check attached policies
aws iam list-attached-role-policies --role-name ecsTaskExecutionRole
```

#### 2. Health Check Failures

**Symptoms:**
- Tasks start but are marked unhealthy
- Load balancer shows unhealthy targets

**Solutions:**

**a) Verify health endpoint:**
```bash
# Get task public IP
aws ecs describe-tasks --cluster modresorts-cluster --tasks <task-id> --region us-east-1 --query 'tasks[0].attachments[0].details[?name==`networkInterfaceId`].value' --output text

# Get public IP from ENI
aws ec2 describe-network-interfaces --network-interface-ids <eni-id> --query 'NetworkInterfaces[0].Association.PublicIp' --output text

# Test health endpoint
curl http://<public-ip>:8080/health
```

**b) Adjust health check settings:**
- Increase `startPeriod` for slow-starting applications
- Increase `interval` and `timeout` values
- Reduce `retries` count

**c) Check security group rules:**
```bash
# Verify inbound rules allow port 8080
aws ec2 describe-security-groups --group-ids <security-group-id>
```

#### 3. Service Not Accessible

**Symptoms:**
- Tasks are running and healthy
- Cannot access application via load balancer

**Solutions:**

**a) Verify load balancer configuration:**
```bash
# Check target group health
aws elbv2 describe-target-health --target-group-arn <target-group-arn>

# Verify listener rules
aws elbv2 describe-listeners --load-balancer-arn <alb-arn>
```

**b) Check security group rules:**
- ALB security group must allow inbound HTTP/HTTPS
- Task security group must allow inbound from ALB

**c) Verify subnet routing:**
- Subnets must have route to Internet Gateway
- NAT Gateway required for private subnets

#### 4. High Memory Usage

**Symptoms:**
- Tasks being killed due to OOM (Out of Memory)
- High memory utilization in CloudWatch

**Solutions:**

**a) Adjust JVM heap size:**
```bash
# Update JAVA_OPTS in task definition
"environment": [
  {
    "name": "JAVA_OPTS",
    "value": "-Xmx768m -Xms384m -XX:MaxRAMPercentage=75.0"
  }
]
```

**b) Increase task memory:**
- Update task definition with higher memory allocation
- Ensure CPU/memory combination is valid for Fargate

**c) Analyze memory leaks:**
```bash
# Enable JVM memory debugging
"environment": [
  {
    "name": "JAVA_OPTS",
    "value": "-Xmx512m -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=/tmp"
  }
]
```

#### 5. Deployment Failures

**Symptoms:**
- Service update fails
- New tasks don't start during deployment

**Solutions:**

**a) Check deployment circuit breaker:**
```bash
# Describe service to see deployment status
aws ecs describe-services --cluster modresorts-cluster --services modresorts-service --region us-east-1
```

**b) Rollback to previous version:**
```bash
# List task definition revisions
aws ecs list-task-definitions --family-prefix modresorts-task

# Update service to previous revision
aws ecs update-service \
  --cluster modresorts-cluster \
  --service modresorts-service \
  --task-definition modresorts-task:1 \
  --region us-east-1
```

**c) Force new deployment:**
```bash
aws ecs update-service \
  --cluster modresorts-cluster \
  --service modresorts-service \
  --force-new-deployment \
  --region us-east-1
```

### Debugging Commands

**View task logs:**
```bash
# Get task ID
TASK_ID=$(aws ecs list-tasks --cluster modresorts-cluster --service-name modresorts-service --region us-east-1 --query 'taskArns[0]' --output text | cut -d'/' -f3)

# View logs
aws logs tail /ecs/modresorts --follow --filter-pattern "$TASK_ID" --region us-east-1
```

**Execute commands in running container:**
```bash
# Enable ECS Exec (one-time setup)
aws ecs update-service \
  --cluster modresorts-cluster \
  --service modresorts-service \
  --enable-execute-command \
  --region us-east-1

# Execute command
aws ecs execute-command \
  --cluster modresorts-cluster \
  --task <task-id> \
  --container modresorts \
  --interactive \
  --command "/bin/bash"
```

---

## Security Considerations

### 1. Container Security

**Use non-root user:**
- Dockerfile creates and uses `appuser` for running the application
- Reduces attack surface if container is compromised

**Minimize image size:**
- Multi-stage build reduces final image size
- Fewer packages mean fewer vulnerabilities

**Scan images for vulnerabilities:**
```bash
# Enable ECR image scanning
aws ecr put-image-scanning-configuration \
  --repository-name modresorts \
  --image-scanning-configuration scanOnPush=true \
  --region us-east-1

# View scan results
aws ecr describe-image-scan-findings \
  --repository-name modresorts \
  --image-id imageTag=latest \
  --region us-east-1
```

### 2. Network Security

**Use private subnets:**
- Deploy tasks in private subnets
- Use NAT Gateway for outbound internet access
- Only ALB should be in public subnets

**Implement security groups:**
```bash
# Task security group: Allow only from ALB
aws ec2 authorize-security-group-ingress \
  --group-id <task-sg-id> \
  --protocol tcp \
  --port 8080 \
  --source-group <alb-sg-id>

# ALB security group: Allow HTTP/HTTPS from internet
aws ec2 authorize-security-group-ingress \
  --group-id <alb-sg-id> \
  --protocol tcp \
  --port 80 \
  --cidr 0.0.0.0/0
```

**Enable VPC Flow Logs:**
```bash
aws ec2 create-flow-logs \
  --resource-type VPC \
  --resource-ids <vpc-id> \
  --traffic-type ALL \
  --log-destination-type cloud-watch-logs \
  --log-group-name /aws/vpc/flowlogs
```

### 3. Secrets Management

**Never hardcode secrets:**
- Use AWS Secrets Manager or Parameter Store
- Reference secrets in task definition

**Example with Secrets Manager:**
```bash
# Create secret
aws secretsmanager create-secret \
  --name modresorts/db-password \
  --secret-string "your-secure-password" \
  --region us-east-1

# Update task definition to use secret
"secrets": [
  {
    "name": "DB_PASSWORD",
    "valueFrom": "arn:aws:secretsmanager:us-east-1:123456789:secret:modresorts/db-password"
  }
]
```

### 4. IAM Best Practices

**Principle of least privilege:**
- Grant only necessary permissions
- Use separate roles for execution and task

**Example task role policy:**
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
aws cloudtrail create-trail \
  --name modresorts-trail \
  --s3-bucket-name modresorts-cloudtrail-logs
```

**Enable ECS container insights:**
```bash
aws ecs update-cluster-settings \
  --cluster modresorts-cluster \
  --settings name=containerInsights,value=enabled
```

---

## Scaling and Management

### Auto Scaling

**Configure Service Auto Scaling:**

1. **Register scalable target:**
```bash
aws application-autoscaling register-scalable-target \
  --service-namespace ecs \
  --resource-id service/modresorts-cluster/modresorts-service \
  --scalable-dimension ecs:service:DesiredCount \
  --min-capacity 2 \
  --max-capacity 10 \
  --region us-east-1
```

2. **Create scaling policy (CPU-based):**
```bash
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

3. **Create scaling policy (Memory-based):**
```bash
aws application-autoscaling put-scaling-policy \
  --service-namespace ecs \
  --resource-id service/modresorts-cluster/modresorts-service \
  --scalable-dimension ecs:service:DesiredCount \
  --policy-name memory-scaling-policy \
  --policy-type TargetTrackingScaling \
  --target-tracking-scaling-policy-configuration '{
    "TargetValue": 80.0,
    "PredefinedMetricSpecification": {
      "PredefinedMetricType": "ECSServiceAverageMemoryUtilization"
    },
    "ScaleInCooldown": 300,
    "ScaleOutCooldown": 60
  }' \
  --region us-east-1
```

### Manual Scaling

**Scale service up or down:**
```bash
aws ecs update-service \
  --cluster modresorts-cluster \
  --service modresorts-service \
  --desired-count 5 \
  --region us-east-1
```

### Blue/Green Deployments

**Using AWS CodeDeploy:**

1. **Create CodeDeploy application:**
```bash
aws deploy create-application \
  --application-name modresorts-app \
  --compute-platform ECS
```

2. **Create deployment group:**
```bash
aws deploy create-deployment-group \
  --application-name modresorts-app \
  --deployment-group-name modresorts-dg \
  --service-role-arn arn:aws:iam::123456789:role/CodeDeployServiceRole \
  --ecs-services clusterName=modresorts-cluster,serviceName=modresorts-service \
  --load-balancer-info targetGroupPairInfoList=[{targetGroups=[{name=modresorts-tg-blue},{name=modresorts-tg-green}],prodTrafficRoute={listenerArns=[arn:aws:elasticloadbalancing:us-east-1:123456789:listener/app/modresorts-alb/...]}}] \
  --deployment-style deploymentType=BLUE_GREEN,deploymentOption=WITH_TRAFFIC_CONTROL \
  --blue-green-deployment-configuration '{
    "terminateBlueInstancesOnDeploymentSuccess": {
      "action": "TERMINATE",
      "terminationWaitTimeInMinutes": 5
    },
    "deploymentReadyOption": {
      "actionOnTimeout": "CONTINUE_DEPLOYMENT"
    }
  }'
```

### Rolling Updates

**Update service with new task definition:**
```bash
# Register new task definition
aws ecs register-task-definition --cli-input-json file://ecs/task-definition.json

# Update service
aws ecs update-service \
  --cluster modresorts-cluster \
  --service modresorts-service \
  --task-definition modresorts-task:2 \
  --deployment-configuration '{
    "maximumPercent": 200,
    "minimumHealthyPercent": 50
  }' \
  --region us-east-1
```

### Maintenance and Updates

**Drain tasks for maintenance:**
```bash
# Set desired count to 0
aws ecs update-service \
  --cluster modresorts-cluster \
  --service modresorts-service \
  --desired-count 0 \
  --region us-east-1

# Wait for tasks to stop
aws ecs wait services-stable \
  --cluster modresorts-cluster \
  --services modresorts-service \
  --region us-east-1
```

**Update task definition:**
```bash
# Make changes to task-definition.json
# Register new version
aws ecs register-task-definition --cli-input-json file://ecs/task-definition.json

# Update service with new version
aws ecs update-service \
  --cluster modresorts-cluster \
  --service modresorts-service \
  --task-definition modresorts-task:3 \
  --force-new-deployment \
  --region us-east-1
```

---

## Technology-Specific Notes

### Java 8 and Tomcat 9.0

**JVM Optimization:**
- The application uses Java 8 with Tomcat 9.0
- JVM is configured for container environments
- Heap size is set to 512MB max, 256MB min
- Container-aware JVM flags are enabled

**Tomcat Configuration:**
- Default connector port: 8080
- Session timeout: 30 minutes (configured in web.xml)
- Servlet 3.1 specification

**WAR Deployment:**
- WAR file is deployed as ROOT.war
- Application is accessible at root context (/)
- No context path prefix required

**Health Check Implementation:**
- Custom HealthCheckServlet provides health status
- Responds to both `/health` and `/actuator/health`
- Returns JSON with application status

### Maven Build Process

**Build optimization:**
- Dependencies are cached in Docker layer
- Source code is copied after dependency resolution
- Tests are skipped during Docker build (`-DskipTests`)

**Build artifacts:**
- Output: `target/modresorts-2.0.0.war`
- Size: Approximately 15-20 MB
- Includes all dependencies and resources

---

## Additional Resources

### AWS Documentation
- [ECS Fargate Documentation](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/AWS_Fargate.html)
- [ECS Task Definitions](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definitions.html)
- [ECS Service Auto Scaling](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/service-auto-scaling.html)

### Docker Documentation
- [Dockerfile Best Practices](https://docs.docker.com/develop/develop-images/dockerfile_best-practices/)
- [Multi-stage Builds](https://docs.docker.com/develop/develop-images/multistage-build/)

### Java and Tomcat
- [Tomcat 9 Documentation](https://tomcat.apache.org/tomcat-9.0-doc/)
- [Java Container Support](https://docs.oracle.com/javase/8/docs/technotes/guides/vm/gctuning/considerations.html)

---

## Support and Troubleshooting

For issues or questions:
1. Check CloudWatch Logs for application errors
2. Review ECS service events for deployment issues
3. Verify security group and network configuration
4. Consult AWS Support or community forums

---

**Document Version**: 1.0  
**Last Updated**: 2024  
**Application Version**: 2.0.0
