package com.acme.modres.config;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.secretsmanager.SecretsManagerClient;

/**
 * AWS Configuration for cloud-native services
 * Configures S3 for storage and Secrets Manager for credential management
 */
@Configuration
public class AwsConfig {

  @Value("${aws.region:us-east-1}")
  private String awsRegion;

  @Bean
  public S3Client s3Client() {
    return S3Client.builder()
        .region(Region.of(awsRegion))
        .build();
  }

  @Bean
  public SecretsManagerClient secretsManagerClient() {
    return SecretsManagerClient.builder()
        .region(Region.of(awsRegion))
        .build();
  }
}
