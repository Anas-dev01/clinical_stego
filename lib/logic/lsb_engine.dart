import 'dart:io';
import 'dart:convert';
import 'dart:math'; 
import 'package:image/image.dart' as img;

class LsbEngine {
  /// MODULE 2: Conceal Clinical Record
  /// Receives an Image object and returns a Stego-Image object
  static img.Image embedData(img.Image image, String data) {
    // Convert encrypted string to binary bits
    // We add a null terminator '\u0000' so we know where the message ends later
    List<int> dataBytes = utf8.encode("$data\u0000");
    List<int> bits = _toBits(dataBytes);

    // Validation: Check if the image is large enough
    if (bits.length > image.width * image.height) {
      throw Exception("Image too small to hold this clinical record.");
    }

    int bitIndex = 0;
    // Work on a copy to keep originalImage pure for metrics
    img.Image stegoImage = image.clone(); 

    for (int y = 0; y < stegoImage.height; y++) {
      for (int x = 0; x < stegoImage.width; x++) {
        if (bitIndex >= bits.length) break;

        img.Pixel pixel = stegoImage.getPixel(x, y);
        int r = pixel.r.toInt();
        
        // LSB Substitution in Red Channel
        if (bits[bitIndex] == 1) {
          r = r | 1;
        } else {
          r = r & ~1;
        }

        stegoImage.setPixelR(x, y, r);
        bitIndex++;
      }
      if (bitIndex >= bits.length) break;
    }
    return stegoImage;
  }

  /// NEW: Quantitative Security Metrics
  static Map<String, double> calculateMetrics(img.Image original, img.Image stego) {
    double totalSqrDiff = 0;
    for (int y = 0; y < original.height; y++) {
      for (int x = 0; x < original.width; x++) {
        var p1 = original.getPixel(x, y);
        var p2 = stego.getPixel(x, y);
        double diff = (p1.r - p2.r).toDouble();
        totalSqrDiff += diff * diff;
      }
    }
    double mse = totalSqrDiff / (original.width * original.height);
    double psnr = (mse == 0) ? 100.0 : 10 * (log(pow(255, 2) / mse) / ln10);
    return {"mse": mse, "psnr": psnr};
  }

  /// MODULE 3: Retrieve Clinical Record
  static Future<String?> extractData(File stegoImageFile) async {
    final bytes = await stegoImageFile.readAsBytes();
    img.Image? image = img.decodeImage(bytes);
    if (image == null) return null;

    List<int> bits = [];
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        img.Pixel pixel = image.getPixel(x, y);
        bits.add(pixel.r.toInt() & 1);
      }
    }

    // Inside lsb_engine.dart -> extractData function
    List<int> resultBytes = [];
    for (int i = 0; i < bits.length; i += 8) {
      if (i + 8 > bits.length) break;
      int byte = 0;
      for (int bit = 0; bit < 8; bit++) {
        byte = (byte << 1) | bits[i + bit];
      }
      
      if (byte == 0) break; // Stop exactly at the null terminator
      resultBytes.add(byte);
    }

    String decoded = utf8.decode(resultBytes, allowMalformed: true);
    return decoded; // Return the full string
  }

  static List<int> _toBits(List<int> bytes) {
    return bytes.expand((b) => 
      Iterable.generate(8, (i) => (b >> (7 - i)) & 1)
    ).toList();
  }
}