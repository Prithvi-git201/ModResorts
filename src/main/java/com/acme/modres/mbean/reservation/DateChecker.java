package com.acme.modres.mbean.reservation;

import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.time.format.DateTimeParseException;
import java.util.List;

import com.acme.modres.Constants;

/**
 * Cloud-native date checker using java.time API instead of legacy java.util.Date.
 * This ensures consistent timezone handling across distributed cloud environments.
 */
public class DateChecker implements Runnable {
  ReservationCheckerData data;
  List<Reservation> reservations;

  public DateChecker(ReservationCheckerData data) {
    this.data = data;
    this.reservations = data.getReservationList().getReservations();
  }

  public void run() {
    DateTimeFormatter formatter = DateTimeFormatter.ofPattern(Constants.DATA_FORMAT);
    
    for (int i = 0; i < reservations.size(); i++) {
      Reservation reservation = reservations.get(i);
      LocalDate selectedDate = data.getSelectedDateAsLocalDate();

      try {
        LocalDate fromDate = LocalDate.parse(reservation.getFromDate(), formatter);
        LocalDate toDate = LocalDate.parse(reservation.getToDate(), formatter);
        
        if (selectedDate.isAfter(fromDate) && selectedDate.isBefore(toDate)) {
          data.setAvailablility(false);
          return; // Exit early if not available
        }
      } catch (DateTimeParseException ex) {
        System.err.println("Failed to parse date: " + ex.getMessage());
        ex.printStackTrace();
      }
    }
    data.setAvailablility(true);
  }
}
