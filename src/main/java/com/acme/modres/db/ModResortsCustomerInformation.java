package com.acme.modres.db;

import org.springframework.stereotype.Repository;
import org.springframework.beans.factory.annotation.Autowired;

import javax.sql.DataSource;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.ArrayList;

/**
 * Cloud-native repository using Spring Data JPA patterns.
 * Removed EJB 2.x annotations (@Singleton, @Startup) and replaced with Spring @Repository.
 * Uses HikariCP connection pooling (configured via Spring Boot) for efficient database connections.
 */
@Repository
public class ModResortsCustomerInformation {
  private static final String SELECT_CUSTOMERS_QUERY = "SELECT INFO FROM CUSTOMER";

  @Autowired
  private DataSource dataSource;

  public ArrayList<String> getCustomerInformation() {
    ArrayList<String> customerInfo = new ArrayList<>();
    
    // Use try-with-resources for automatic resource management
    try (Connection conn = dataSource.getConnection();
         PreparedStatement stmt = conn.prepareStatement(SELECT_CUSTOMERS_QUERY);
         ResultSet rs = stmt.executeQuery()) {

      // Process the results
      while (rs.next()) {
        String info = rs.getString("INFO");
        customerInfo.add(info);
      }

    } catch (SQLException e) {
      e.printStackTrace();
      // In production, use proper logging framework
      System.err.println("Database error: " + e.getMessage());
    }
    
    return customerInfo;
  }
}
