# Multi-stage Dockerfile for ModResorts Java WAR Application
# Stage 1: Build stage using Maven
FROM maven:3.9.4-eclipse-temurin-8 AS builder

# Set working directory
WORKDIR /workspace

# Copy pom.xml first for dependency caching
COPY pom.xml .

# Download dependencies (cached layer)
RUN mvn dependency:go-offline -B

# Copy source code and web content
COPY src ./src
COPY WebContent ./WebContent

# Build the WAR file
RUN mvn clean package -DskipTests -B

# Stage 2: Runtime stage using Tomcat with Java 8
FROM tomcat:9.0-jre8-temurin-jammy

# Set metadata
LABEL maintainer="ModResorts Team"
LABEL application="modresorts"
LABEL version="2.0.0"

# Remove default Tomcat applications
RUN rm -rf /usr/local/tomcat/webapps/*

# Copy WAR file from builder stage
COPY --from=builder /workspace/target/modresorts-2.0.0.war /usr/local/tomcat/webapps/ROOT.war

# Create non-root user for security
RUN groupadd -r appuser && useradd -r -g appuser appuser

# Create directories for logs and configuration
RUN mkdir -p /usr/local/tomcat/logs /usr/local/tomcat/conf/Catalina/localhost && \
    chown -R appuser:appuser /usr/local/tomcat

# Set environment variables for JVM tuning
ENV JAVA_OPTS="-Xmx512m -Xms256m -XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -Djava.security.egd=file:/dev/./urandom"
ENV CATALINA_OPTS="-Duser.timezone=UTC"

# Expose application port
EXPOSE 8080

# Switch to non-root user
USER appuser

# Health check using application's native health endpoint
# Note: Tomcat image includes curl, so we can use it for health checks
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD curl -f http://localhost:8080/health || exit 1

# Start Tomcat
CMD ["catalina.sh", "run"]
