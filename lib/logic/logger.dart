import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart'; // Added for Widget support

class AuditLogger {
  // 1. Get the path to the hidden audit file
  static Future<File> _getLogFile() async {
    final directory = await getApplicationDocumentsDirectory();
    // We use a .log extension which is standard for system events
    return File('${directory.path}/clinical_audit.log');
  }

  // 2. The core function to write an event
  static Future<void> logEvent(String action) async {
    final file = await _getLogFile();
    final timestamp = DateTime.now().toString().split(
      '.',
    )[0]; // Cleaned up milliseconds

    // Format: [2025-12-23 09:30:00] ACTION: User performed X
    final logEntry = "[$timestamp] ACTION: $action\n";

    // 'append' mode ensures we don't overwrite previous logs
    await file.writeAsString(logEntry, mode: FileMode.append);
  }

  // 3. Read the logs (for the secret Supervisor view later)
  static Future<String> readLogs() async {
    try {
      final file = await _getLogFile();
      if (await file.exists()) {
        return await file.readAsString();
      }
      return "No logs recorded yet.";
    } catch (e) {
      return "Error reading logs: $e";
    }
  }

  // 4. UI Component for displaying forensic logs
  static Widget buildAuditTile(String logEntry) {
    // Determine the icon and color based on the action
    IconData logIcon = Icons.info_outline;
    Color logColor = Colors.blueGrey;

    if (logEntry.contains("HIDDEN")) {
      logIcon = Icons.enhanced_encryption;
      logColor = Colors.orange.shade700;
    } else if (logEntry.contains("RETRIEVED")) {
      logIcon = Icons.lock_open;
      logColor = Colors.green.shade700;
    } else if (logEntry.contains("EXPORTED")) {
      logIcon = Icons.picture_as_pdf;
      logColor = Colors.red.shade700;
    }

    return ListTile(
      leading: Icon(logIcon, color: logColor),
      title: Text(
        logEntry,
        style: const TextStyle(
          fontSize: 13,
          fontFamily: 'monospace',
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: const Text("Level: Security Audit"),
      dense: true,
    );
  }
}
