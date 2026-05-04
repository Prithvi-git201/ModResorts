package com.acme.modres.mbean.reservation;

import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.util.List;

import com.acme.modres.Constants;

public class DateChecker implements Runnable {
  ReservationCheckerData data;
  List<Reservation> reservations;

  public DateChecker(ReservationCheckerData data) {
    this.data = data;
    this.reservations = data.getReservationList().getReservations();
  }

  public void run() {
    // Use java.time API for cloud-native date handling (UTC standardized)
    DateTimeFormatter formatter = DateTimeFormatter.ofPattern(Constants.DATA_FORMAT);
    LocalDate selectedDate = data.getSelectedDateAsLocalDate();
    
    for (int i = 0; i < reservations.size(); i++) {
      Reservation reservation = reservations.get(i);

      try {
        LocalDate fromDate = LocalDate.parse(reservation.getFromDate(), formatter);
        LocalDate toDate = LocalDate.parse(reservation.getToDate(), formatter);
        
        if (selectedDate.isAfter(fromDate) && selectedDate.isBefore(toDate)) {
          data.setAvailablility(false);
          return;
        }
      } catch (Exception ex) {
        ex.printStackTrace();
      }
    }
    data.setAvailablility(true);
  }
}
