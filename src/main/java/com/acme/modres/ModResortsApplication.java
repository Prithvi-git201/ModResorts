package com.acme.modres;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.web.servlet.ServletComponentScan;
import org.springframework.context.annotation.Bean;
import org.springframework.session.data.redis.config.annotation.web.http.EnableRedisHttpSession;

import com.zaxxer.hikari.HikariConfig;
import com.zaxxer.hikari.HikariDataSource;

import javax.sql.DataSource;

/**
 * Spring Boot Application for ModResorts - Cloud-Native Configuration
 * 
 * This application is configured for AWS cloud deployment with:
 * - Embedded Tomcat (no external application server needed)
 * - HikariCP connection pooling for database connections
 * - Redis session management via Amazon ElastiCache
 * - AWS SDK integration for S3 and Secrets Manager
 * - Externalized configuration via environment variables
 */
@SpringBootApplication
@ServletComponentScan
@EnableRedisHttpSession
public class ModResortsApplication {

    public static void main(String[] args) {
        SpringApplication.run(ModResortsApplication.class, args);
    }

    /**
     * Configure HikariCP DataSource for cloud-native database connections
     * Connection pool settings are optimized for containerized environments
     */
    @Bean
    public DataSource dataSource() {
        HikariConfig config = new HikariConfig();
        
        // Load database configuration from environment variables
        config.setJdbcUrl(System.getenv().getOrDefault("DB_URL", "jdbc:postgresql://localhost:5432/modresorts"));
        config.setUsername(System.getenv().getOrDefault("DB_USERNAME", "modresorts"));
        config.setPassword(System.getenv().getOrDefault("DB_PASSWORD", "password"));
        config.setDriverClassName(System.getenv().getOrDefault("DB_DRIVER", "org.postgresql.Driver"));
        
        // HikariCP optimizations for cloud environments
        config.setMaximumPoolSize(Integer.parseInt(System.getenv().getOrDefault("DB_POOL_SIZE", "10")));
        config.setMinimumIdle(Integer.parseInt(System.getenv().getOrDefault("DB_MIN_IDLE", "2")));
        config.setConnectionTimeout(30000); // 30 seconds
        config.setIdleTimeout(600000); // 10 minutes
        config.setMaxLifetime(1800000); // 30 minutes
        config.setAutoCommit(true);
        config.setConnectionTestQuery("SELECT 1");
        
        return new HikariDataSource(config);
    }
}
