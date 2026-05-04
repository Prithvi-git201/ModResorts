# Multi-stage Dockerfile for ModResorts Spring Boot Application
# Target: AWS ECS Fargate Deployment
# Java Version: 8
# Build Tool: Maven
# Base Image: eclipse-temurin:8-jdk (explicitly specified)

# ============================================
# Stage 1: Builder - Build the application
# ============================================
FROM maven:3.9.4-eclipse-temurin-8 AS builder

# Set working directory
WORKDIR /workspace

# Copy Maven configuration files first for dependency caching
COPY pom.xml .

# Download dependencies (cached layer if pom.xml doesn't change)
RUN mvn dependency:go-offline -B

# Copy source code
COPY src ./src
COPY WebContent ./WebContent

# Build the application (skip tests for faster builds)
RUN mvn clean package -DskipTests -B

# ============================================
# Stage 2: Runtime - Create minimal runtime image
# ============================================
FROM eclipse-temurin:8-jdk

# Set working directory
WORKDIR /app

# Create non-root user for security
RUN groupadd -r appuser && useradd -r -g appuser appuser

# Copy the built WAR file from builder stage
COPY --from=builder /workspace/target/*.war app.war

# Create directories for logs and config
RUN mkdir -p /app/logs /app/config && \
    chown -R appuser:appuser /app

# Switch to non-root user
USER appuser

# Set JVM options for containerized environment
ENV JAVA_OPTS="-Xmx512m -Xms256m -XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -XX:+UnlockExperimentalVMOptions -Djava.security.egd=file:/dev/./urandom"

# Set Spring Boot profile for Docker
ENV SPRING_PROFILES_ACTIVE=docker

# Set timezone
ENV TZ=UTC

# Expose application port
EXPOSE 8080

# Health check is handled by ECS service - no curl/wget needed in image

# Run the application
ENTRYPOINT ["sh", "-c", "java $JAVA_OPTS -jar app.war"]
