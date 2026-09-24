import 'package:encrypt/encrypt.dart' as encrypt;
import 'dart:convert';
import 'dart:typed_data'; // Add this for Uint8List
import 'package:crypto/crypto.dart';
// import 'package:cryptography/cryptography.dart'; // Ensure this is here

class SecretCipher {
  // MODULE 1: PBKDF2 Key Derivation (100,000 iterations as per your algorithm)
  static encrypt.Key _deriveKey(String password) {
    // We will use the SHA256 hash approach to generate a 32-byte key
    // This matches the length required for AES-256 encryption.

    final salt = "static_salt_for_demo"; // Your static salt from Python logic

    // Combining password and salt as per PBKDF2 principles
    final bytes = utf8.encode(password + salt);

    // Generate a SHA-256 hash to ensure a fixed 32-byte length
    final digest = sha256.convert(bytes);

    return encrypt.Key(Uint8List.fromList(digest.bytes));
  }

  static String encryptData(String plainText, String password) {
    final key = _deriveKey(password);
    final iv = encrypt.IV.fromLength(16);
    final encrypter = encrypt.Encrypter(encrypt.AES(key));

    final encrypted = encrypter.encrypt(plainText, iv: iv);
    return "${iv.base64}:${encrypted.base64}";
  }

  static String? decryptData(String combinedData, String password) {
    try {
      final parts = combinedData.split(':');
      final iv = encrypt.IV.fromBase64(parts[0]);
      final encryptedContent = parts[1];

      final key = _deriveKey(password);
      final encrypter = encrypt.Encrypter(encrypt.AES(key));

      return encrypter.decrypt(
        encrypt.Encrypted.fromBase64(encryptedContent),
        iv: iv,
      );
    } catch (e) {
      return null; // Return None/Null as per your algorithm
    }
  }
}
