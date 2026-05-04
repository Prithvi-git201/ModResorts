# ModResorts - Cloud-Ready Application

## Overview
ModResorts has been migrated to a cloud-native architecture for deployment on AWS. The application is now packaged as an executable JAR with embedded Tomcat, eliminating the need for external application servers.

## Cloud Readiness Improvements

### 1. **Packaging Migration**
- **Before**: WAR file requiring WebSphere/Tomcat
- **After**: Executable JAR with embedded Tomcat (Spring Boot)
- **Benefit**: Simplified containerization and deployment on ECS/EKS/Fargate

### 2. **Storage Migration**
- **Before**: Local file system operations
- **After**: Amazon S3 for persistent storage
- **Benefit**: Durable, scalable storage that survives container restarts

### 3. **Session Management**
- **Before**: WebSphere-specific session clustering
- **After**: Amazon ElastiCache (Redis) via Spring Session
- **Benefit**: Stateless application enabling horizontal scaling

### 4. **Secrets Management**
- **Before**: Hardcoded API keys and environment variables
- **After**: AWS Secrets Manager
- **Benefit**: Secure credential management with automatic rotation

### 5. **Database Connection Pooling**
- **Before**: Direct JDBC connections with EJB
- **After**: HikariCP connection pooling with Spring Data JPA
- **Benefit**: Optimized connection management for cloud environments

### 6. **Date/Time Handling**
- **Before**: java.util.Date with local timezone dependencies
- **After**: java.time API (LocalDate, Instant) with UTC standardization
- **Benefit**: Consistent time handling across distributed cloud regions

### 7. **Framework Migration**
- **Before**: EJB 2.x with heavy container dependencies
- **After**: Spring Boot with lightweight dependency injection
- **Benefit**: Cloud-native microservices architecture

## Environment Variables

Configure the following environment variables for cloud deployment:

### Application Configuration
```bash
SERVER_PORT=8080                    # Application server port
AWS_REGION=us-east-1               # AWS region
```

### S3 Configuration
```bash
S3_BUCKET_NAME=modresorts-data     # S3 bucket for file storage
```

### Redis/ElastiCache Configuration
```bash
REDIS_HOST=your-elasticache-endpoint.cache.amazonaws.com
REDIS_PORT=6379
REDIS_PASSWORD=your-redis-password  # Optional
REDIS_SSL=true                      # Enable for production
```

### Database Configuration
```bash
DB_URL=jdbc:postgresql://your-rds-endpoint:5432/modresorts
DB_USERNAME=modresorts
DB_PASSWORD=your-db-password
DB_DRIVER=org.postgresql.Driver
DB_POOL_SIZE=10
```

### Secrets Manager
```bash
WEATHER_API_KEY_SECRET=modresorts/weather-api-key
```

## Building the Application

```bash
mvn clean package
```

This produces an executable JAR: `target/modresorts-2.0.0.jar`

## Running Locally

```bash
java -jar target/modresorts-2.0.0.jar
```

## AWS Deployment Options

### Option 1: Amazon ECS (Elastic Container Service)
1. Build Docker image with the executable JAR
2. Push to Amazon ECR
3. Create ECS task definition
4. Deploy to ECS cluster

### Option 2: Amazon EKS (Elastic Kubernetes Service)
1. Build Docker image
2. Create Kubernetes deployment manifests
3. Deploy to EKS cluster

### Option 3: AWS Fargate
1. Build Docker image
2. Create Fargate task definition
3. Deploy serverless containers

### Option 4: AWS Elastic Beanstalk
1. Upload JAR file directly
2. Configure environment variables
3. Deploy with zero infrastructure management

## Required AWS Resources

### 1. Amazon S3 Bucket
```bash
aws s3 mb s3://modresorts-data --region us-east-1
```

### 2. Amazon ElastiCache (Redis)
```bash
aws elasticache create-cache-cluster \
  --cache-cluster-id modresorts-session \
  --engine redis \
  --cache-node-type cache.t3.micro \
  --num-cache-nodes 1
```

### 3. AWS Secrets Manager
```bash
aws secretsmanager create-secret \
  --name modresorts/weather-api-key \
  --secret-string "your-weather-api-key"
```

### 4. Amazon RDS (Optional)
```bash
aws rds create-db-instance \
  --db-instance-identifier modresorts-db \
  --db-instance-class db.t3.micro \
  --engine postgres \
  --master-username modresorts \
  --master-user-password your-password \
  --allocated-storage 20
```

## IAM Permissions

The application requires the following IAM permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::modresorts-data",
        "arn:aws:s3:::modresorts-data/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue"
      ],
      "Resource": "arn:aws:secretsmanager:*:*:secret:modresorts/*"
    }
  ]
}
```

## Health Checks

Spring Boot Actuator endpoints are available for container health checks:

- **Health**: `http://localhost:8080/actuator/health`
- **Info**: `http://localhost:8080/actuator/info`
- **Metrics**: `http://localhost:8080/actuator/metrics`

## Monitoring and Logging

- Logs are written to stdout/stderr for CloudWatch Logs integration
- Structured logging format for easy parsing
- Actuator metrics for Prometheus/CloudWatch integration

## Security Considerations

1. **Secrets**: Never commit secrets to source control
2. **IAM Roles**: Use IAM roles for EC2/ECS instead of access keys
3. **Network**: Deploy in private subnets with security groups
4. **Encryption**: Enable encryption at rest for S3, RDS, and ElastiCache
5. **TLS**: Use Application Load Balancer with TLS termination

## Migration Notes

### Removed Dependencies
- `javax.ejb` (EJB 2.x)
- `com.ibm.websphere` (WebSphere-specific APIs)
- WAR packaging

### Added Dependencies
- Spring Boot Starter Web
- Spring Boot Starter Data JPA
- Spring Session Data Redis
- AWS SDK for Java v2 (S3, Secrets Manager)
- HikariCP (connection pooling)

### Code Changes
- Replaced `java.util.Date` with `java.time.LocalDate`
- Replaced local file operations with S3 operations
- Replaced WebSphere session management with Spring Session
- Replaced hardcoded secrets with AWS Secrets Manager
- Added try-with-resources for automatic resource management
- Migrated EJB to Spring Service components

## Support

For issues or questions, contact the cloud migration team.
