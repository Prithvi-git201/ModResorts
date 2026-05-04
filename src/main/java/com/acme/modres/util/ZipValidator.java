package com.acme.modres.util;

import java.io.ByteArrayInputStream;
import java.io.File;
import java.io.IOException;
import java.util.Enumeration;
import java.util.zip.ZipEntry;
import java.util.zip.ZipException;
import java.util.zip.ZipFile;
import java.util.zip.ZipInputStream;

public class ZipValidator extends ZipFile {

  private File file;
  private ByteArrayInputStream byteStream;

  public ZipValidator(File file) throws ZipException, IOException {
    super(file);
    this.file = file;
  }

  /**
   * Constructor for validating zip data from memory (cloud-native approach)
   */
  public ZipValidator(ByteArrayInputStream byteStream) throws IOException {
    super(File.createTempFile("temp", ".zip"));
    this.byteStream = byteStream;
  }

  public boolean isValid() throws Throwable {
    if (byteStream != null) {
      // Validate zip from memory stream
      try (ZipInputStream zis = new ZipInputStream(byteStream)) {
        ZipEntry entry = zis.getNextEntry();
        return entry != null;
      }
    } else if (file != null && file.exists()) {
      // Validate zip from file
      try (ZipValidator zipFile = new ZipValidator(file)) {
        Enumeration<? extends ZipEntry> entries = zipFile.entries();
        return entries.hasMoreElements();
      }
    }
    return false;
  }

}
