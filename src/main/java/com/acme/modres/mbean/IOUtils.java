package com.acme.modres.mbean;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;

import com.acme.modres.mbean.reservation.ReservationList;
import com.acme.modres.util.JsonInputStream;

import software.amazon.awssdk.core.ResponseInputStream;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.s3.model.GetObjectResponse;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;

public final class IOUtils {

  private static S3Client s3Client;
  private static String s3BucketName;
  
  static {
    // Initialize S3 client for cloud-native storage
    s3Client = S3Client.builder().build();
    s3BucketName = System.getenv().getOrDefault("S3_BUCKET_NAME", "modresorts-data");
  }

  /**
   * Get input stream from classpath resource or S3
   * This replaces the local file system dependency
   */
  public static InputStream getInputStreamFromResource(String path) {
    InputStream initialStream = null;
    try {
      // First try to load from classpath
      initialStream = IOUtils.class.getClassLoader().getResourceAsStream(path);
      
      if (initialStream == null) {
        // If not in classpath, try to load from S3
        try {
          GetObjectRequest getObjectRequest = GetObjectRequest.builder()
              .bucket(s3BucketName)
              .key("config/" + path)
              .build();
          
          ResponseInputStream<GetObjectResponse> s3Object = s3Client.getObject(getObjectRequest);
          
          // Read S3 object into byte array
          ByteArrayOutputStream baos = new ByteArrayOutputStream();
          byte[] buffer = new byte[1024];
          int length;
          while ((length = s3Object.read(buffer)) >= 0) {
            baos.write(buffer, 0, length);
          }
          s3Object.close();
          
          initialStream = new ByteArrayInputStream(baos.toByteArray());
        } catch (Exception e) {
          System.err.println("Resource not found in classpath or S3: " + path);
          e.printStackTrace();
        }
      }
    } catch (Exception e) {
      e.printStackTrace();
    }
    
    return initialStream;
  }

  /**
   * Write data to S3 instead of local temporary file system
   */
  public static void writeToS3(String key, byte[] data) throws IOException {
    try {
      PutObjectRequest putObjectRequest = PutObjectRequest.builder()
          .bucket(s3BucketName)
          .key(key)
          .build();
      
      s3Client.putObject(putObjectRequest, RequestBody.fromBytes(data));
    } catch (Exception e) {
      throw new IOException("Failed to write to S3: " + e.getMessage(), e);
    }
  }

  public static OpMetadataList getOpListFromConfig() {
    try (InputStream is = getInputStreamFromResource("ops.json")) {
      if (is == null) {
        return new OpMetadataList(); // empty default
      }
      
      // Read stream into byte array for JsonInputStream
      ByteArrayOutputStream baos = new ByteArrayOutputStream();
      byte[] buffer = new byte[1024];
      int length;
      while ((length = is.read(buffer)) >= 0) {
        baos.write(buffer, 0, length);
      }
      
      try (JsonInputStream jis = new JsonInputStream(new ByteArrayInputStream(baos.toByteArray()))) {
        OpMetadataList opList = (OpMetadataList) jis.parseJsonAs(OpMetadataList.class);
        return opList;
      }
    } catch (IOException e) {
      e.printStackTrace();
      return new OpMetadataList(); // empty default
    }
  }

  public static ReservationList getReservationListFromConfig() {
    try (InputStream is = getInputStreamFromResource("reservations.json")) {
      if (is == null) {
        return new ReservationList(); // empty default
      }
      
      // Read stream into byte array for JsonInputStream
      ByteArrayOutputStream baos = new ByteArrayOutputStream();
      byte[] buffer = new byte[1024];
      int length;
      while ((length = is.read(buffer)) >= 0) {
        baos.write(buffer, 0, length);
      }
      
      try (JsonInputStream jis = new JsonInputStream(new ByteArrayInputStream(baos.toByteArray()))) {
        ReservationList reservationList = (ReservationList) jis.parseJsonAs(ReservationList.class);
        return reservationList;
      }
    } catch (IOException e) {
      e.printStackTrace();
      return new ReservationList(); // empty default
    }
  }

}
