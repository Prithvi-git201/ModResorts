package com.acme.modres.util;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;

import com.google.gson.Gson;

/**
 * Cloud-native JSON input stream that works with any InputStream.
 * This allows reading from classpath resources, S3, or any other source.
 */
public class JsonInputStream implements AutoCloseable {

  private InputStream inputStream;

  public JsonInputStream(InputStream inputStream) {
    this.inputStream = inputStream;
  }

  public Object parseJsonAs(Class<?> cls) {
    if (inputStream == null) {
      return null;
    }
    
    try {
      Gson gson = new Gson();
      BufferedReader reader = new BufferedReader(new InputStreamReader(inputStream));
      return gson.fromJson(reader, cls);
    } catch (Exception e) {
      System.err.println("Error parsing JSON: " + e.getMessage());
      e.printStackTrace();
      return null;
    }
  }

  @Override
  public void close() throws IOException {
    if (inputStream != null) {
      inputStream.close();
    }
  }
}
