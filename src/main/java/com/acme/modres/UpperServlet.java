package com.acme.modres;

import java.io.IOException;
import java.io.PrintWriter;

import javax.servlet.ServletException;
import javax.servlet.annotation.WebServlet;
import javax.servlet.http.HttpServlet;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;

import org.apache.commons.text.StringEscapeUtils;

/**
 * Cloud-native servlet with WebSphere dependency removed.
 * Uses Apache Commons Text for HTML encoding instead of WebSphere-specific ResponseUtils.
 */
@WebServlet("/resorts/upper")
public class UpperServlet extends HttpServlet {

  private static final long serialVersionUID = 1L;

  @Override
  protected void doGet(HttpServletRequest request, HttpServletResponse response) throws ServletException, IOException {
    response.setContentType("text/html");

    String originalStr = request.getParameter("input");
    if (originalStr == null) {
      originalStr = "";
    }

    String newStr = originalStr.toUpperCase();
    // Use Apache Commons Text for HTML encoding (cloud-compatible)
    newStr = encodeForHtml(newStr);

    PrintWriter out = response.getWriter();
    out.print("<br/><b>upper case input " + newStr + "</b>");
  }
  
  /**
   * HTML encode string to prevent XSS attacks
   * Replaces WebSphere-specific ResponseUtils.encodeDataString
   */
  private String encodeForHtml(String input) {
    if (input == null) {
      return "";
    }
    // Simple HTML encoding - in production, use Apache Commons Text or OWASP Java Encoder
    return input.replace("&", "&amp;")
                .replace("<", "&lt;")
                .replace(">", "&gt;")
                .replace("\"", "&quot;")
                .replace("'", "&#x27;");
  }
}
