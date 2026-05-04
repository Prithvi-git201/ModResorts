package com.acme.modres.util;

import java.io.File;
import java.io.IOException;
import java.util.Enumeration;
import java.util.zip.ZipEntry;
import java.util.zip.ZipException;
import java.util.zip.ZipFile;

public class ZipValidator {

  private File file;

  public ZipValidator(File file) {
    this.file = file;
  }

  public boolean isValid() throws IOException {
    if (file.exists()) {
      try (ZipFile zipFile = new ZipFile(file)) {
        Enumeration<? extends ZipEntry> entries = zipFile.entries();
        if (!entries.hasMoreElements()) {
          return true;
        }
      }
    }
    return false;
  }

}
