package com.acme.modres;

import javax.servlet.ServletException;
import javax.servlet.annotation.WebServlet;
import javax.servlet.http.HttpServlet;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.io.PrintWriter;
import java.lang.management.ManagementFactory;
import java.lang.management.MemoryMXBean;
import java.lang.management.RuntimeMXBean;

/**
 * Health check endpoint for container orchestration platforms (ECS, EKS, Kubernetes).
 * Returns application health status in JSON format.
 * 
 * Endpoints:
 * - GET /health - Basic health check
 * - GET /health/live - Liveness probe (is the app running?)
 * - GET /health/ready - Readiness probe (is the app ready to serve traffic?)
 */
@WebServlet(urlPatterns = {"/health", "/health/live", "/health/ready"})
public class HealthCheckServlet extends HttpServlet {
    private static final long serialVersionUID = 1L;
    
    @Override
    protected void doGet(HttpServletRequest request, HttpServletResponse response) 
            throws ServletException, IOException {
        
        String path = request.getServletPath();
        response.setContentType("application/json");
        response.setCharacterEncoding("UTF-8");
        
        try {
            boolean isHealthy = checkHealth(path);
            
            if (isHealthy) {
                response.setStatus(HttpServletResponse.SC_OK);
                writeHealthResponse(response, "UP", path);
            } else {
                response.setStatus(HttpServletResponse.SC_SERVICE_UNAVAILABLE);
                writeHealthResponse(response, "DOWN", path);
            }
        } catch (Exception e) {
            response.setStatus(HttpServletResponse.SC_SERVICE_UNAVAILABLE);
            writeErrorResponse(response, e);
        }
    }
    
    /**
     * Performs health checks based on the endpoint path.
     */
    private boolean checkHealth(String path) {
        if ("/health/live".equals(path)) {
            // Liveness check - is the JVM running?
            return true;
        } else if ("/health/ready".equals(path)) {
            // Readiness check - is the app ready to serve requests?
            return checkReadiness();
        } else {
            // General health check
            return checkReadiness();
        }
    }
    
    /**
     * Checks if the application is ready to serve traffic.
     */
    private boolean checkReadiness() {
        try {
            // Check if JVM has enough memory
            MemoryMXBean memoryBean = ManagementFactory.getMemoryMXBean();
            long usedMemory = memoryBean.getHeapMemoryUsage().getUsed();
            long maxMemory = memoryBean.getHeapMemoryUsage().getMax();
            
            // If memory usage is above 95%, consider not ready
            if (maxMemory > 0 && (usedMemory * 100.0 / maxMemory) > 95) {
                return false;
            }
            
            // Add additional readiness checks here (database, external services, etc.)
            
            return true;
        } catch (Exception e) {
            return false;
        }
    }
    
    /**
     * Writes a successful health response.
     */
    private void writeHealthResponse(HttpServletResponse response, String status, String path) 
            throws IOException {
        RuntimeMXBean runtimeBean = ManagementFactory.getRuntimeMXBean();
        MemoryMXBean memoryBean = ManagementFactory.getMemoryMXBean();
        
        long uptimeSeconds = runtimeBean.getUptime() / 1000;
        long usedMemory = memoryBean.getHeapMemoryUsage().getUsed() / (1024 * 1024);
        long maxMemory = memoryBean.getHeapMemoryUsage().getMax() / (1024 * 1024);
        
        StringBuilder json = new StringBuilder();
        json.append("{\n");
        json.append("  \"status\": \"").append(status).append("\",\n");
        json.append("  \"application\": \"ModResorts\",\n");
        json.append("  \"version\": \"2.0.0\",\n");
        json.append("  \"endpoint\": \"").append(path).append("\",\n");
        json.append("  \"uptime\": ").append(uptimeSeconds).append(",\n");
        json.append("  \"memory\": {\n");
        json.append("    \"used\": ").append(usedMemory).append(",\n");
        json.append("    \"max\": ").append(maxMemory).append(",\n");
        json.append("    \"unit\": \"MB\"\n");
        json.append("  },\n");
        json.append("  \"timestamp\": ").append(System.currentTimeMillis()).append("\n");
        json.append("}\n");
        
        PrintWriter out = response.getWriter();
        out.print(json.toString());
        out.flush();
    }
    
    /**
     * Writes an error response.
     */
    private void writeErrorResponse(HttpServletResponse response, Exception e) throws IOException {
        StringBuilder json = new StringBuilder();
        json.append("{\n");
        json.append("  \"status\": \"DOWN\",\n");
        json.append("  \"error\": \"").append(e.getMessage()).append("\",\n");
        json.append("  \"timestamp\": ").append(System.currentTimeMillis()).append("\n");
        json.append("}\n");
        
        PrintWriter out = response.getWriter();
        out.print(json.toString());
        out.flush();
    }
}
