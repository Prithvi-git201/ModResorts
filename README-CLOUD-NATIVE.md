# ModResorts Backend - Cloud-Native Application

## Overview
This application has been modernized for cloud deployment on AWS with the following improvements:

### Cloud Readiness Fixes Applied

1. **Packaging Migration** (Blockers 18-19)
   - Converted from WAR to executable JAR with embedded Tomcat
   - Removed dependency on external application servers
   - Enabled containerization for ECS/EKS/Fargate

2. **File System Dependencies Removed** (Blockers 1-4, 6)
   - Replaced local file operations with Amazon S3
   - Migrated temporary file storage to S3
   - Removed hard-coded file paths
   - Resources now loaded from classpath

3. **Resource Management** (Blocker 5)
   - Implemented try-with-resources for automatic cleanup
   - Prevents resource leaks in containerized environments

4. **Secrets Management** (Blocker 7)
   - Migrated hardcoded API keys to AWS Secrets Manager
   - Fallback to environment variables for flexibility
   - Automatic secret rotation support

5. **Legacy Framework Migration** (Blockers 8-9)
   - Removed EJB 2.x annotations
   - Migrated to Spring Boot with Spring Data JPA
   - Replaced with cloud-native dependency injection

6. **Date/Time Handling** (Blockers 10-14)
   - Migrated from java.util.Date to java.time API
   - Standardized on UTC for consistency
   - Eliminated timezone-related issues

7. **Stateful Middleware Removed** (Blockers 15-17)
   - Removed WebSphere-specific dependencies
   - Externalized session state to Amazon ElastiCache (Redis)
   - Enabled horizontal scaling

## AWS Services Integration

### Required AWS Services
- **Amazon S3**: File storage and exports
- **Amazon RDS**: Database (PostgreSQL/MySQL)
- **Amazon ElastiCache (Redis)**: Session management
- **AWS Secrets Manager**: Secure credential storage
- **Amazon ECS/EKS/Fargate**: Container orchestration

### Environment Variables

```bash
# Server Configuration
PORT=8080

# Database Configuration
DB_URL=jdbc:postgresql://your-rds-endpoint:5432/modresorts
DB_USERNAME=modresorts
DB_PASSWORD=<from-secrets-manager>
DB_DRIVER=org.postgresql.Driver
DB_POOL_SIZE=10
DB_MIN_IDLE=2

# Redis Configuration (ElastiCache)
REDIS_HOST=your-elasticache-endpoint
REDIS_PORT=6379
REDIS_PASSWORD=<from-secrets-manager>
REDIS_SSL=true

# AWS Configuration
AWS_REGION=us-east-1
S3_BUCKET_NAME=modresorts-data

# Weather API Key (stored in Secrets Manager)
# Secret Name: modresorts/weather-api-key
```

## Building the Application

```bash
# Build executable JAR
mvn clean package

# Run locally
java -jar target/modresorts-2.0.0.jar

# Build Docker image (handled separately)
# See Dockerfile in deployment artifacts
```

## Database Setup

The application uses HikariCP connection pooling with the following optimizations:
- Maximum pool size: 10 connections
- Minimum idle: 2 connections
- Connection timeout: 30 seconds
- Idle timeout: 10 minutes
- Max lifetime: 30 minutes

## Session Management

Sessions are externalized to Amazon ElastiCache (Redis) using Spring Session:
- Enables stateless application instances
- Supports horizontal scaling
- Session data survives container restarts

## Health Checks

Spring Boot Actuator endpoints are enabled:
- `/actuator/health` - Application health status
- `/actuator/info` - Application information
- `/actuator/metrics` - Application metrics

## Security Considerations

1. **Secrets Management**: All credentials stored in AWS Secrets Manager
2. **Network Security**: Use VPC security groups and NACLs
3. **Encryption**: Enable encryption at rest (RDS, S3, ElastiCache)
4. **TLS/SSL**: Enable HTTPS for all external communication

## Deployment Architecture

```
Internet
    |
Application Load Balancer
    |
ECS/EKS Cluster (Auto-scaling)
    |
    +-- ModResorts Containers (Stateless)
    |
    +-- Amazon RDS (PostgreSQL)
    +-- Amazon ElastiCache (Redis)
    +-- Amazon S3 (File Storage)
    +-- AWS Secrets Manager (Credentials)
```

## Monitoring and Logging

- Application logs are written to stdout/stderr
- Use CloudWatch Logs for centralized logging
- CloudWatch Metrics for monitoring
- X-Ray for distributed tracing (optional)

## Scaling Considerations

The application is now stateless and can scale horizontally:
- Session state in Redis
- File storage in S3
- Database connection pooling
- No local file system dependencies

## Migration Notes

### Removed Dependencies
- `javaee-api` (replaced with Spring Boot)
- `was_public` (WebSphere-specific)
- EJB 2.x annotations

### Added Dependencies
- Spring Boot 2.7.14
- AWS SDK for Java v2
- Spring Session Redis
- HikariCP (via Spring Boot)

### Breaking Changes
- Application now runs as executable JAR (not WAR)
- Requires Redis for session management
- Requires S3 bucket for file operations
- Database credentials must be externalized

## Support

For issues or questions, contact the cloud migration team.
