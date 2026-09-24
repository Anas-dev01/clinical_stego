import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

class CabinetService {
  static Database? _db;

  // 1. Initialize the Cabinet Database
  static Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDB();
    return _db!;
  }

  static Future<Database> _initDB() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'custech_cabinet.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        // This table only holds index data, NO medical secrets
        await db.execute('''
          CREATE TABLE patients(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            matric_number TEXT UNIQUE,
            student_name TEXT,
            department TEXT,
            folder_path TEXT,
            date_registered TEXT
          )
        ''');
      },
    );
  }

  // 2. Automated Safe Folder Creation (Android 10+ Compliant)
  static Future<Directory> _createPatientFolder(String matricNumber) async {
    // Sanitize the matric number so it doesn't break folder paths (e.g., replace / with _)
    String safeMatric = matricNumber.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');

    // We use the Documents directory so it is organized and safe
    final directory = await getApplicationDocumentsDirectory();
    final folderPath = '${directory.path}/CUSTECH_Clinical_Stego/$safeMatric';

    final folder = Directory(folderPath);
    if (!(await folder.exists())) {
      await folder.create(recursive: true);
    }
    return folder;
  }

  // 3. Register a New Student (Creates DB entry AND physical folder)
  static Future<Map<String, dynamic>> registerStudent({
    required String matricNumber,
    required String name,
    required String department,
  }) async {
    final db = await database;

    try {
      // Create their physical storage folder
      final folder = await _createPatientFolder(matricNumber);
      final date = DateTime.now().toIso8601String();

      await db.insert('patients', {
        'matric_number': matricNumber.toUpperCase(),
        'student_name': name,
        'department': department,
        'folder_path': folder.path,
        'date_registered': date,
      });

      return {
        'success': true,
        'message': 'Student registered. Folder created at: ${folder.path}',
        'folderPath': folder.path,
      };
    } catch (e) {
      // The UNIQUE constraint on matric_number will trigger this if they exist
      return {
        'success': false,
        'message':
            'Error: A student with this Matric Number is already registered.',
      };
    }
  }

  // 4. Search for a Student (By Matric Number or Name)
  static Future<List<Map<String, dynamic>>> searchPatient(String query) async {
    final db = await database;
    return await db.query(
      'patients',
      where: 'matric_number LIKE ? OR student_name LIKE ?',
      whereArgs: ['%${query.toUpperCase()}%', '%$query%'],
    );
  }

  static Future<Map<String, dynamic>?> findPatientByMatric(
    String matricNumber,
  ) async {
    final db = await database;
    final rows = await db.query(
      'patients',
      where: 'matric_number = ?',
      whereArgs: [matricNumber.toUpperCase()],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  // 5. Fetch all students (For the front desk dashboard list)
  static Future<List<Map<String, dynamic>>> getAllPatients() async {
    final db = await database;
    return await db.query('patients', orderBy: 'date_registered DESC');
  }
}
