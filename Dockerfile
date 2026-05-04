# Multi-stage Dockerfile for ModResorts JavaEE WAR Application
# Stage 1: Build stage using Maven
FROM maven:3.9.4-eclipse-temurin-8 AS builder

# Set working directory
WORKDIR /workspace

# Copy pom.xml first for dependency caching
COPY pom.xml .

# Download dependencies (this layer will be cached if pom.xml doesn't change)
RUN mvn dependency:go-offline -B

# Copy the entire project source
COPY src ./src
COPY WebContent ./WebContent

# Build the WAR file
RUN mvn clean package -DskipTests -B

# Stage 2: Runtime stage using Tomcat with Eclipse Temurin JRE
FROM tomcat:9.0-jre8

# Remove default Tomcat applications
RUN rm -rf /usr/local/tomcat/webapps/*

# Copy the WAR file from builder stage to Tomcat webapps
COPY --from=builder /workspace/target/*.war /usr/local/tomcat/webapps/ROOT.war

# Create non-root user for security
RUN groupadd -r appuser && useradd -r -g appuser appuser

# Create directories for logs and configuration
RUN mkdir -p /app/logs /app/config && \
    chown -R appuser:appuser /app && \
    chown -R appuser:appuser /usr/local/tomcat

# Set environment variables for JVM tuning
ENV JAVA_OPTS="-Xmx512m -Xms256m -XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -Djava.security.egd=file:/dev/./urandom"
ENV CATALINA_OPTS="-Duser.timezone=UTC"

# Expose Tomcat port
EXPOSE 8080

# Switch to non-root user
USER appuser

# Start Tomcat
CMD ["catalina.sh", "run"]
