package com.acme.modres;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.PrintWriter;
import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.time.format.DateTimeParseException;
import java.util.List;
import java.util.logging.Logger;
import java.util.zip.ZipEntry;
import java.util.zip.ZipOutputStream;

import javax.servlet.ServletException;
import javax.servlet.annotation.WebServlet;
import javax.servlet.http.HttpServlet;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;

import com.acme.modres.mbean.IOUtils;
import com.acme.modres.mbean.reservation.ReservationCheckerData;
import com.acme.modres.mbean.reservation.Reservation;
import com.acme.modres.util.ZipValidator;

import software.amazon.awssdk.auth.credentials.DefaultCredentialsProvider;
import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;

@WebServlet({ "/resorts/availability" })
public class AvailabilityCheckerServlet extends HttpServlet {
  private static final long serialVersionUID = 1L;

  private static final Logger logger = Logger.getLogger(AvailabilityCheckerServlet.class.getName());

  private ReservationCheckerData reservationCheckerData;
  
  private S3Client s3Client;
  private String s3BucketName;

  @Override
  public void init() {
    // load reserved dates
    this.reservationCheckerData = new ReservationCheckerData(IOUtils.getReservationListFromConfig());
    
    // Initialize S3 client for cloud storage
    String awsRegion = System.getenv().getOrDefault("AWS_REGION", "us-east-1");
    this.s3BucketName = System.getenv().getOrDefault("S3_BUCKET_NAME", "modresorts-data");
    
    this.s3Client = S3Client.builder()
        .region(Region.of(awsRegion))
        .credentialsProvider(DefaultCredentialsProvider.create())
        .build();
  }
  
  @Override
  public void destroy() {
    if (s3Client != null) {
      s3Client.close();
    }
  }

  @Override
  protected void doGet(HttpServletRequest request, HttpServletResponse response) throws IOException, ServletException {

    String methodName = "doGet";
    logger.entering(AvailabilityCheckerServlet.class.getName(), methodName);
    int statusCode = 200;

    String selectedDateStr = request.getParameter("date");
    boolean parsedDate = reservationCheckerData.setSelectedDate(selectedDateStr);
    if (!parsedDate || reservationCheckerData.getReservationList() == null) {
      statusCode = 500;
      reservationCheckerData.setAvailablility(false);
    } else {
      List<Reservation> reservations = reservationCheckerData.getReservationList().getReservations();
      boolean isAvailible = true;

      DateTimeFormatter formatter = DateTimeFormatter.ofPattern(Constants.DATA_FORMAT);
      
      for (Reservation reservation : reservations) {
        try {
          LocalDate fromDate = LocalDate.parse(reservation.getFromDate(), formatter);
          LocalDate toDate = LocalDate.parse(reservation.getToDate(), formatter);
          LocalDate selectedDate = reservationCheckerData.getSelectedDateAsLocalDate();

          if (selectedDate.isAfter(fromDate) && selectedDate.isBefore(toDate)) {
            isAvailible = false;
            break;
          }
        } catch (DateTimeParseException ex) {
          logger.severe("Failed to parse date: " + ex.getMessage());
          ex.printStackTrace();
        }
      }

      reservationCheckerData.setAvailablility(isAvailible);

      // Adjust the status code based on availability
      if (!isAvailible) {
        statusCode = 201;
      }
    }

    // Send the response
    PrintWriter out = response.getWriter();
    response.setContentType("application/json");
    response.setCharacterEncoding("UTF-8");
    out.print("{\"availability\": \"" + String.valueOf(reservationCheckerData.isAvailible()) + "\"}");
    response.setStatus(statusCode);
  }

  /**
   * Returns the weather information for a given city
   */
  protected void doPost(HttpServletRequest request, HttpServletResponse response)
      throws ServletException, IOException {

    doGet(request, response);
  }

  /**
   * Export reservations to Amazon S3 instead of local file system
   */
  protected int exportRevervations(String selectedDateStr) {
    // Use try-with-resources to ensure automatic resource cleanup
    try (InputStream reservationStream = IOUtils.class.getClassLoader().getResourceAsStream("reservations.json");
         ByteArrayOutputStream baos = new ByteArrayOutputStream();
         ZipOutputStream zipOut = new ZipOutputStream(baos)) {
      
      if (reservationStream == null) {
        logger.severe("reservations.json not found in classpath");
        return -1;
      }
      
      // Create zip entry
      ZipEntry zipEntry = new ZipEntry("reservations.json");
      zipOut.putNextEntry(zipEntry);

      // Copy data to zip
      byte[] bytes = new byte[1024];
      int length;
      while ((length = reservationStream.read(bytes)) >= 0) {
        zipOut.write(bytes, 0, length);
      }
      
      zipOut.closeEntry();
      zipOut.finish();

      // Upload to S3 instead of local file system
      byte[] zipData = baos.toByteArray();
      String s3Key = "exports/reservations-" + selectedDateStr + ".zip";
      
      PutObjectRequest putObjectRequest = PutObjectRequest.builder()
          .bucket(s3BucketName)
          .key(s3Key)
          .contentType("application/zip")
          .build();
      
      s3Client.putObject(putObjectRequest, RequestBody.fromBytes(zipData));
      
      logger.info("Successfully exported reservations to S3: " + s3Key);
      return 0;
      
    } catch (IOException e) {
      logger.severe("Error exporting reservations: " + e.getMessage());
      e.printStackTrace();
      return -1;
    } catch (Exception e) {
      logger.severe("Unexpected error: " + e.getMessage());
      e.printStackTrace();
      return -1;
    }
  }

}
