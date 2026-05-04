package com.acme.modres.mbean;

import java.io.IOException;
import java.io.InputStream;

import com.acme.modres.mbean.reservation.ReservationList;
import com.acme.modres.util.JsonInputStream;

/**
 * Cloud-native IOUtils that reads from classpath resources instead of local file system.
 * For cloud deployments, configuration files should be packaged in the application JAR
 * or loaded from external configuration services like AWS Systems Manager Parameter Store.
 */
public final class IOUtils {

  /**
   * Load resource from classpath - cloud-compatible approach
   * Resources are packaged within the application JAR and don't require local file system access
   */
  public static InputStream getResourceAsStream(String path) {
    return IOUtils.class.getClassLoader().getResourceAsStream(path);
  }

  public static OpMetadataList getOpListFromConfig() {
    try (InputStream is = getResourceAsStream("ops.json")) {
      if (is == null) {
        System.err.println("ops.json not found in classpath");
        return new OpMetadataList(); // return empty default
      }
      
      try (JsonInputStream jis = new JsonInputStream(is)) {
        OpMetadataList opList = (OpMetadataList) jis.parseJsonAs(OpMetadataList.class);
        return opList;
      }
    } catch (IOException e) {
      e.printStackTrace();
      return new OpMetadataList(); // return empty default
    }
  }

  public static ReservationList getReservationListFromConfig() {
    try (InputStream is = getResourceAsStream("reservations.json")) {
      if (is == null) {
        System.err.println("reservations.json not found in classpath");
        return new ReservationList(); // return empty default
      }
      
      try (JsonInputStream jis = new JsonInputStream(is)) {
        ReservationList reservationList = (ReservationList) jis.parseJsonAs(ReservationList.class);
        return reservationList;
      }
    } catch (IOException e) {
      e.printStackTrace();
      return new ReservationList(); // return empty default
    }
  }

}
