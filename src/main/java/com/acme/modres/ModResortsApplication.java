package com.acme.modres;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.web.servlet.ServletComponentScan;
import org.springframework.context.annotation.ComponentScan;

/**
 * Spring Boot Application class for containerized deployment.
 * Enables Spring Boot Actuator for health check endpoint at /actuator/health
 * 
 * This replaces WebSphere-specific server dependencies with embedded Spring Boot server
 * for AWS ECS/EKS containerized deployment.
 */
@SpringBootApplication
@ServletComponentScan
@ComponentScan(basePackages = "com.acme.modres")
public class ModResortsApplication {

    public static void main(String[] args) {
        SpringApplication.run(ModResortsApplication.class, args);
    }
}
