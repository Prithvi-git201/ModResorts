package com.acme.modres;

import javax.servlet.ServletException;
import javax.servlet.annotation.WebServlet;
import javax.servlet.http.HttpServlet;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.io.PrintWriter;

/**
 * Health check endpoint for container orchestration platforms (ECS, EKS, Kubernetes)
 * Returns HTTP 200 with JSON status when the application is healthy
 */
@WebServlet({ "/health", "/actuator/health" })
public class HealthCheckServlet extends HttpServlet {
  private static final long serialVersionUID = 1L;

  @Override
  protected void doGet(HttpServletRequest request, HttpServletResponse response) 
      throws ServletException, IOException {
    
    response.setContentType("application/json");
    response.setCharacterEncoding("UTF-8");
    
    // Perform basic health checks
    boolean isHealthy = performHealthChecks();
    
    if (isHealthy) {
      response.setStatus(HttpServletResponse.SC_OK);
      PrintWriter out = response.getWriter();
      out.print("{\"status\":\"UP\",\"application\":\"ModResorts\",\"version\":\"2.0.0\"}");
      out.flush();
    } else {
      response.setStatus(HttpServletResponse.SC_SERVICE_UNAVAILABLE);
      PrintWriter out = response.getWriter();
      out.print("{\"status\":\"DOWN\",\"application\":\"ModResorts\",\"version\":\"2.0.0\"}");
      out.flush();
    }
  }

  /**
   * Perform basic health checks
   * Can be extended to check database connectivity, external services, etc.
   */
  private boolean performHealthChecks() {
    try {
      // Basic check - if we can execute this code, the servlet container is running
      // Add additional checks as needed:
      // - Database connectivity
      // - External service availability
      // - Memory/resource checks
      return true;
    } catch (Exception e) {
      e.printStackTrace();
      return false;
    }
  }

  @Override
  protected void doHead(HttpServletRequest request, HttpServletResponse response) 
      throws ServletException, IOException {
    // Support HEAD requests for lightweight health checks
    boolean isHealthy = performHealthChecks();
    response.setStatus(isHealthy ? HttpServletResponse.SC_OK : HttpServletResponse.SC_SERVICE_UNAVAILABLE);
  }
}
