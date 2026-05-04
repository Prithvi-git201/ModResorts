package com.acme.modres.security;

import jakarta.servlet.http.Cookie;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

/**
 * Security helper for managing SSO cookies
 * This is a stub implementation to replace WebSphere-specific security features
 */
public class WSSecurityHelper {
    
    /**
     * Revokes SSO cookies by invalidating the session and clearing cookies
     * @param request the HTTP request
     * @param response the HTTP response
     */
    public static void revokeSSOCookies(HttpServletRequest request, HttpServletResponse response) {
        // Invalidate the session
        if (request.getSession(false) != null) {
            request.getSession().invalidate();
        }
        
        // Clear common SSO cookies
        Cookie[] cookies = request.getCookies();
        if (cookies != null) {
            for (Cookie cookie : cookies) {
                // Clear the cookie by setting max age to 0
                Cookie clearCookie = new Cookie(cookie.getName(), "");
                clearCookie.setMaxAge(0);
                clearCookie.setPath("/");
                response.addCookie(clearCookie);
            }
        }
    }
}
