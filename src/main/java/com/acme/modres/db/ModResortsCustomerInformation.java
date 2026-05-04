package com.acme.modres.db;

import javax.annotation.PostConstruct;
import javax.annotation.Resource;
import javax.enterprise.context.ApplicationScoped;
import javax.sql.DataSource;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.ArrayList;
import java.util.logging.Level;
import java.util.logging.Logger;

/**
 * Replaced @Singleton with @ApplicationScoped for better container compatibility.
 * For distributed caching in containerized environments, integrate with Redis/ElastiCache
 * using Spring Cache or similar abstraction with REDIS_HOST and REDIS_PORT environment variables.
 */
@ApplicationScoped
public class ModResortsCustomerInformation {
  private static final Logger logger = Logger.getLogger(ModResortsCustomerInformation.class.getName());
  private static final String SELECT_CUSTOMERS_QUERY = "SELECT INFO FROM CUSTOMER";

  // Removing DB connection for ease of demo setup
  // @Resource(lookup = "jdbc/ModResortsJndi")
  private DataSource dataSource;
  
  // For production containerized deployment, use distributed cache
  // Example: Redis connection configured via environment variables
  // REDIS_HOST, REDIS_PORT, REDIS_PASSWORD
  
  @PostConstruct
  public void init() {
    logger.info("ModResortsCustomerInformation initialized. For distributed caching, configure Redis via environment variables: REDIS_HOST, REDIS_PORT, REDIS_PASSWORD");
  }

  public ArrayList<String> getCustomerInformation() {
    Connection conn = null;
    PreparedStatement stmt = null;
    ResultSet rs = null;
    ArrayList<String> customerInfo = new ArrayList<>();

    try {
      // Get a connection from the injected data source
      conn = dataSource.getConnection();
      // Create a prepared statement
      stmt = conn.prepareStatement(SELECT_CUSTOMERS_QUERY);
      // Execute the query
      rs = stmt.executeQuery();

      // Process the results
      while (rs.next()) {
        String info = rs.getString("INFO");
        customerInfo.add(info);
      }

    } catch (SQLException e) {
      logger.log(Level.SEVERE, "Database error while fetching customer information", e);
    } finally {
      // Close the result set, statement, and connection
      try {
        if (rs != null)
          rs.close();
        if (stmt != null)
          stmt.close();
        if (conn != null)
          conn.close();
      } catch (SQLException e) {
        logger.log(Level.WARNING, "Error closing database resources", e);
      }
    }
    return customerInfo;
  }
}
