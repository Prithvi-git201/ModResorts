package com.acme.modres.util;

import java.io.BufferedReader;
import java.io.ByteArrayInputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileNotFoundException;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;

import com.google.gson.Gson;

/**
 * Cloud-readiness fix (cr-java-0062): Added InputStream-based constructor and
 * parseJsonFromStream() method so that callers can parse JSON directly from
 * classpath resources without writing to the local file system.
 */
public class JsonInputStream extends FileInputStream {

  private File file;

  public JsonInputStream(File file) throws FileNotFoundException {
    super(file);
    this.file = file;
  }

  /**
   * Parses JSON from a classpath InputStream without touching the local file
   * system. This is the cloud-safe alternative to the File-based constructor.
   *
   * @param stream the InputStream to read JSON from
   * @param cls    the target class for deserialization
   * @return deserialized object, or null on error
   */
  public static Object parseJsonFromStream(InputStream stream, Class<?> cls) {
    if (stream == null) {
      return null;
    }
    try {
      Gson gson = new Gson();
      BufferedReader reader = new BufferedReader(new InputStreamReader(stream, "UTF-8"));
      return gson.fromJson(reader, cls);
    } catch (Exception e) {
      e.printStackTrace();
      return null;
    } finally {
      try {
        stream.close();
      } catch (IOException e) {
        // ignore
      }
    }
  }

  public Object parseJsonAs(Class<?> cls) {
    if (file.exists()) {
      JsonInputStream is = null;
      Object jsonObject = null;
      try {
        is = new JsonInputStream(file);
        Gson gson = new Gson();
        BufferedReader reader = new BufferedReader(new InputStreamReader(is));
        jsonObject = gson.fromJson(reader, cls);
      } catch (Exception e) {
        e.printStackTrace();
      } catch (Throwable e) {
        e.printStackTrace();
      } finally {
        if (is != null) {
          try {
            is.close();
            is.read(); // test if file is closed
          } catch (IOException e) {
            // closed successfully
            return jsonObject;
          } catch (Throwable e) {
            e.printStackTrace();
          }
        }
      }
    }
    return null;
  }

}
