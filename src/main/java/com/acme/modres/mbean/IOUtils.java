package com.acme.modres.mbean;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.util.logging.Level;
import java.util.logging.Logger;

import com.acme.modres.mbean.reservation.ReservationList;
import com.acme.modres.util.JsonInputStream;

import software.amazon.awssdk.core.ResponseInputStream;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.s3.model.GetObjectResponse;
import software.amazon.awssdk.services.s3.model.NoSuchKeyException;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;
import software.amazon.awssdk.services.s3.model.S3Exception;

/**
 * Utility class for I/O operations.
 *
 * Cloud-readiness fix (cr-java-0112): Eliminated reliance on ephemeral local
 * temporary directories by migrating temporary file operations to Amazon S3.
 * The previous implementation used File.createTempFile() (line 23 of the
 * original source) which wrote to the local /tmp directory — data that is lost
 * on every container restart. All intermediate / temporary data is now stored
 * in and retrieved from Amazon S3, ensuring persistence across container
 * lifecycle events and enabling multi-instance access.
 *
 * Required environment variables:
 *   S3_BUCKET_NAME  – name of the S3 bucket used for intermediate data storage
 *   AWS_REGION      – AWS region for the S3 client (default: us-east-1)
 */
public final class IOUtils {

  private static final Logger logger = Logger.getLogger(IOUtils.class.getName());

  /** Environment variable that holds the S3 bucket name for intermediate data. */
  private static final String ENV_S3_BUCKET = "S3_BUCKET_NAME";

  /** Environment variable that holds the AWS region (defaults to us-east-1). */
  private static final String ENV_AWS_REGION = "AWS_REGION";

  /** Default AWS region when {@value #ENV_AWS_REGION} is not set. */
  private static final String DEFAULT_REGION = "us-east-1";

  // -------------------------------------------------------------------------
  // S3 helper methods — replace File.createTempFile() / local /tmp usage
  // -------------------------------------------------------------------------

  /**
   * Builds a reusable S3Client from environment-variable configuration.
   * Uses the IAM role attached to the container/EC2 instance for credentials
   * (no hard-coded secrets).
   *
   * @return configured {@link S3Client}
   */
  private static S3Client buildS3Client() {
    String region = System.getenv(ENV_AWS_REGION);
    if (region == null || region.isEmpty()) {
      region = DEFAULT_REGION;
    }
    return S3Client.builder()
        .region(Region.of(region))
        .build();
  }

  /**
   * Stores intermediate / temporary data in Amazon S3, replacing the previous
   * pattern of writing to a local temporary file via File.createTempFile().
   *
   * <p>Data stored here survives container restarts and is accessible from all
   * running instances of the application.
   *
   * @param s3Key  the S3 object key under which the data will be stored
   * @param data   the byte array to persist
   * @return {@code true} if the upload succeeded, {@code false} otherwise
   */
  public static boolean storeIntermediateDataToS3(String s3Key, byte[] data) {
    String bucketName = System.getenv(ENV_S3_BUCKET);
    if (bucketName == null || bucketName.isEmpty()) {
      logger.severe("S3_BUCKET_NAME environment variable is not set. "
          + "Cannot store intermediate data to S3.");
      return false;
    }
    try (S3Client s3Client = buildS3Client()) {
      PutObjectRequest putRequest = PutObjectRequest.builder()
          .bucket(bucketName)
          .key(s3Key)
          .build();
      s3Client.putObject(putRequest, RequestBody.fromBytes(data));
      logger.info("Intermediate data stored to S3: s3://" + bucketName + "/" + s3Key);
      return true;
    } catch (S3Exception e) {
      logger.log(Level.SEVERE, "Failed to store intermediate data to S3 key: " + s3Key, e);
      return false;
    }
  }

  /**
   * Retrieves intermediate / temporary data from Amazon S3, replacing the
   * previous pattern of reading from a local temporary file.
   *
   * <p>Falls back to reading the resource from the classpath when the S3 bucket
   * environment variable is not configured (e.g. local development).
   *
   * @param s3Key        the S3 object key to retrieve
   * @param classpathFallback classpath-relative path used when S3 is unavailable
   * @return byte array with the object content, or {@code null} on error
   */
  public static byte[] retrieveIntermediateDataFromS3(String s3Key, String classpathFallback) {
    String bucketName = System.getenv(ENV_S3_BUCKET);
    if (bucketName == null || bucketName.isEmpty()) {
      logger.warning("S3_BUCKET_NAME not set — falling back to classpath resource: "
          + classpathFallback);
      return getBytesFromResource(classpathFallback);
    }
    try (S3Client s3Client = buildS3Client()) {
      GetObjectRequest getRequest = GetObjectRequest.builder()
          .bucket(bucketName)
          .key(s3Key)
          .build();
      try (ResponseInputStream<GetObjectResponse> s3Object = s3Client.getObject(getRequest)) {
        ByteArrayOutputStream buffer = new ByteArrayOutputStream();
        byte[] chunk = new byte[4096];
        int bytesRead;
        while ((bytesRead = s3Object.read(chunk)) != -1) {
          buffer.write(chunk, 0, bytesRead);
        }
        logger.info("Intermediate data retrieved from S3: s3://" + bucketName + "/" + s3Key);
        return buffer.toByteArray();
      }
    } catch (NoSuchKeyException e) {
      logger.warning("S3 key not found: " + s3Key + " — falling back to classpath: "
          + classpathFallback);
      return getBytesFromResource(classpathFallback);
    } catch (S3Exception | IOException e) {
      logger.log(Level.SEVERE, "Failed to retrieve intermediate data from S3 key: " + s3Key, e);
      return null;
    }
  }

  /**
   * Opens an {@link InputStream} backed by data retrieved from Amazon S3.
   *
   * <p>Falls back to the classpath when S3 is not configured, enabling the
   * same code path to work in both cloud and local-development environments.
   *
   * @param s3Key        the S3 object key to retrieve
   * @param classpathFallback classpath-relative path used when S3 is unavailable
   * @return {@link InputStream} for the data, or {@code null} on error
   */
  public static InputStream getStreamFromS3(String s3Key, String classpathFallback) {
    byte[] data = retrieveIntermediateDataFromS3(s3Key, classpathFallback);
    if (data == null) {
      return null;
    }
    return new ByteArrayInputStream(data);
  }

  // -------------------------------------------------------------------------
  // Classpath / in-memory helpers (static resources bundled in the WAR)
  // -------------------------------------------------------------------------

  /**
   * Reads a classpath resource into a byte array without writing to the local
   * file system.
   *
   * <p>Cloud-readiness fix (cr-java-0112): Replaces the previous implementation
   * that used {@code File.createTempFile()} and {@code FileOutputStream} to
   * write the resource to the ephemeral local {@code /tmp} directory. Data is
   * now kept entirely in memory and, when persistence across restarts is
   * required, stored in Amazon S3 via
   * {@link #storeIntermediateDataToS3(String, byte[])}.
   *
   * @param path classpath-relative resource path (e.g. "reservations.json")
   * @return byte array containing the resource content, or {@code null} on error
   */
  public static byte[] getBytesFromResource(String path) {
    InputStream initialStream = null;
    try {
      initialStream = IOUtils.class.getClassLoader().getResourceAsStream(path);
      if (initialStream == null) {
        logger.warning("Classpath resource not found: " + path);
        return null;
      }
      ByteArrayOutputStream buffer = new ByteArrayOutputStream();
      byte[] chunk = new byte[4096];
      int bytesRead;
      while ((bytesRead = initialStream.read(chunk)) != -1) {
        buffer.write(chunk, 0, bytesRead);
      }
      return buffer.toByteArray();
    } catch (Exception e) {
      logger.log(Level.SEVERE, "Error reading classpath resource: " + path, e);
      return null;
    } finally {
      if (initialStream != null) {
        try {
          initialStream.close();
        } catch (IOException e) {
          // ignore close failure
        }
      }
    }
  }

  /**
   * Opens a classpath resource as an {@link InputStream}.
   *
   * @param path classpath-relative resource path
   * @return {@link InputStream} for the resource, or {@code null} if not found
   */
  public static InputStream getStreamFromResource(String path) {
    return IOUtils.class.getClassLoader().getResourceAsStream(path);
  }

  // -------------------------------------------------------------------------
  // Domain-specific config loaders
  // -------------------------------------------------------------------------

  /**
   * Loads the operations configuration from Amazon S3 (with classpath fallback).
   *
   * <p>When {@code S3_BUCKET_NAME} is set the file is read from S3 so that
   * updates to the configuration survive container restarts. When the variable
   * is absent the bundled classpath resource is used (local development).
   *
   * @return parsed {@link OpMetadataList}, or {@code null} on error
   */
  public static OpMetadataList getOpListFromConfig() {
    InputStream stream = getStreamFromS3("ops.json", "ops.json");
    if (stream == null) {
      // Last-resort: try classpath directly
      stream = getStreamFromResource("ops.json");
    }
    if (stream == null) {
      return null;
    }
    return (OpMetadataList) JsonInputStream.parseJsonFromStream(stream, OpMetadataList.class);
  }

  /**
   * Loads the reservations configuration from Amazon S3 (with classpath fallback).
   *
   * <p>When {@code S3_BUCKET_NAME} is set the file is read from S3 so that
   * updates to the reservation data survive container restarts. When the
   * variable is absent the bundled classpath resource is used (local
   * development).
   *
   * @return parsed {@link ReservationList}, or {@code null} on error
   */
  public static ReservationList getReservationListFromConfig() {
    InputStream stream = getStreamFromS3("reservations.json", "reservations.json");
    if (stream == null) {
      // Last-resort: try classpath directly
      stream = getStreamFromResource("reservations.json");
    }
    if (stream == null) {
      return null;
    }
    return (ReservationList) JsonInputStream.parseJsonFromStream(stream, ReservationList.class);
  }

}
