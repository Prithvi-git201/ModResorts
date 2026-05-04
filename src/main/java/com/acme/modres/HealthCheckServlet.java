package com.acme.modres;

import javax.servlet.ServletException;
import javax.servlet.annotation.WebServlet;
import javax.servlet.http.HttpServlet;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.io.PrintWriter;

/**
 * Health check endpoint for containerized deployment.
 * Returns a simple JSON response indicating the application status.
 * This endpoint is used by container orchestration platforms (ECS/EKS)
 * for liveness and readiness probes.
 */
@WebServlet({ "/health", "/actuator/health" })
public class HealthCheckServlet extends HttpServlet {
  private static final long serialVersionUID = 1L;

  @Override
  protected void doGet(HttpServletRequest request, HttpServletResponse response) 
      throws ServletException, IOException {
    
    response.setContentType("application/json");
    response.setCharacterEncoding("UTF-8");
    response.setStatus(HttpServletResponse.SC_OK);
    
    PrintWriter out = response.getWriter();
    
    // Return a simple health status JSON
    String healthStatus = "{"
        + "\"status\":\"UP\","
        + "\"application\":\"ModResorts\","
        + "\"version\":\"2.0.0\","
        + "\"timestamp\":" + System.currentTimeMillis()
        + "}";
    
    out.print(healthStatus);
    out.flush();
  }
  
  @Override
  protected void doHead(HttpServletRequest request, HttpServletResponse response) 
      throws ServletException, IOException {
    // Support HEAD requests for simple health checks
    response.setStatus(HttpServletResponse.SC_OK);
  }
}
