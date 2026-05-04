package com.acme.modres.util;

/**
 * Utility class for encoding response data
 */
public class ResponseUtils {
    
    /**
     * Encodes a string for safe HTML output by escaping special characters
     * @param data the string to encode
     * @return the encoded string
     */
    public static String encodeDataString(String data) {
        if (data == null) {
            return "";
        }
        
        StringBuilder encoded = new StringBuilder();
        for (int i = 0; i < data.length(); i++) {
            char c = data.charAt(i);
            switch (c) {
                case '<':
                    encoded.append("&lt;");
                    break;
                case '>':
                    encoded.append("&gt;");
                    break;
                case '&':
                    encoded.append("&amp;");
                    break;
                case '"':
                    encoded.append("&quot;");
                    break;
                case '\'':
                    encoded.append("&#x27;");
                    break;
                case '/':
                    encoded.append("&#x2F;");
                    break;
                default:
                    encoded.append(c);
                    break;
            }
        }
        return encoded.toString();
    }
}
