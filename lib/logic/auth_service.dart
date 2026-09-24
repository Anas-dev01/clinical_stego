import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class AuthService {
  static Database? _db;

  // Updated Database Initialization with new columns
  // THIS IS WHERE THE DATABASE IS INITIATED
  static Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await openDatabase(
      join(await getDatabasesPath(), 'clinical_auth.db'),
      onCreate: (db, version) => db.execute(
        "CREATE TABLE users(id INTEGER PRIMARY KEY, username TEXT, password TEXT, firstName TEXT, lastName TEXT, honorific TEXT)",
      ),
      version: 1,
    );
    return _db!;
  }

  // Cryptographic hashing for password protection
  static String _hashPassword(String password) {
    return sha256.convert(utf8.encode(password)).toString();
  }

  // Updated Register function to handle 5 positional arguments
  static Future<void> register(String user, String pass, String first, String last, String hon) async {
    final db = await database;
    await db.insert('users', {
      'username': user, 
      'password': _hashPassword(pass),
      'firstName': first,
      'lastName': last,
      'honorific': hon
    });
  }

  // Updated Login function to return User Data Map instead of just a bool
  static Future<Map<String, dynamic>?> login(String user, String pass) async {
    final db = await database;
    final List<Map<String, dynamic>> res = await db.query(
      'users',
      where: "username = ? AND password = ?",
      whereArgs: [user, _hashPassword(pass)],
    );
    
    // Return the first match (the user's row containing name/honorific) or null
    return res.isNotEmpty ? res.first : null;
  }
}
