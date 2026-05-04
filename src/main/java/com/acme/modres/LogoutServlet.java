package com.acme.modres;

import javax.servlet.annotation.WebServlet;
import javax.servlet.http.HttpServlet;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import javax.servlet.http.HttpSession;
import javax.servlet.http.Cookie;

import java.io.IOException;

@WebServlet({ "/logout" })
public class LogoutServlet extends HttpServlet {
  private static final long serialVersionUID = 1L;

  @Override
  protected void doGet(HttpServletRequest request,
      HttpServletResponse response) throws IOException {

    try {
      // Replace WebSphere-specific WSSecurityHelper with standard servlet API
      // Invalidate the session
      HttpSession session = request.getSession(false);
      if (session != null) {
        session.invalidate();
      }
      
      // Clear authentication cookies using standard servlet API
      Cookie[] cookies = request.getCookies();
      if (cookies != null) {
        for (Cookie cookie : cookies) {
          // Clear session-related cookies
          if (cookie.getName().contains("JSESSIONID") || 
              cookie.getName().contains("SESSION") ||
              cookie.getName().contains("SSO")) {
            Cookie clearCookie = new Cookie(cookie.getName(), "");
            clearCookie.setMaxAge(0);
            clearCookie.setPath("/");
            response.addCookie(clearCookie);
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
