package com.acme.modres;

import javax.servlet.annotation.WebServlet;
import javax.servlet.http.HttpServlet;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import javax.servlet.http.HttpSession;

import java.io.IOException;

/**
 * Cloud-native logout servlet using standard servlet session management.
 * Removed WebSphere-specific WSSecurityHelper dependency.
 * Session state is externalized to Amazon ElastiCache (Redis) via Spring Session.
 */
@WebServlet({ "/logout" })
public class LogoutServlet extends HttpServlet {
  private static final long serialVersionUID = 1L;

  @Override
  protected void doGet(HttpServletRequest request,
      HttpServletResponse response) throws IOException {

    try {
      // Invalidate session - works with Spring Session Redis
      HttpSession session = request.getSession(false);
      if (session != null) {
        session.invalidate();
      }
      
      // Clear any authentication cookies
      // In cloud environments, use standard servlet cookie management
      javax.servlet.http.Cookie[] cookies = request.getCookies();
      if (cookies != null) {
        for (javax.servlet.http.Cookie cookie : cookies) {
          if ("JSESSIONID".equals(cookie.getName()) || cookie.getName().startsWith("SESSION")) {
            cookie.setValue("");
            cookie.setPath("/");
            cookie.setMaxAge(0);
            response.addCookie(cookie);
          }
        }
      }
      
    } catch (Exception e) {
      System.err.println("[ERROR] Error logging out");
      e.printStackTrace();
    }

    response.sendRedirect("login.jsp");
  }
}
