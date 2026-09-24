import 'dart:io'; // Add this import
import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'screens/conceal_page.dart';
import 'screens/retrieve_page.dart';
import 'logic/login_page.dart';
import 'logic/logger.dart';

void main() {
  // Check if we are running on Linux, Windows, or macOS
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    // Initialize FFI
    sqfliteFfiInit();
    // Set the database factory to FFI
    databaseFactory = databaseFactoryFfi;
  }

  runApp(const ClinicalStegoApp());
}

class ClinicalStegoApp extends StatelessWidget {
  const ClinicalStegoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Clinical Stego',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.teal, useMaterial3: true),
      // Starts at the Login Portal
      home: const LoginPage(),
    );
  }
}

class Dashboard extends StatelessWidget {
  final Map<String, dynamic> userData; // Receives data from LoginPage

  const Dashboard({super.key, required this.userData});

  // Helper method to show the Secret Audit Trail
  void _showAuditDialog(BuildContext context, String logs) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("📜 System Audit Trail"),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Text(
              logs,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 10),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("CLOSE"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Extract strings safely from the database map
    final String honorific = userData['honorific'] ?? "User";
    final String lastName = userData['lastName'] ?? "Staff";

    String formattedLastName = "";
    if (lastName.isNotEmpty) {
      formattedLastName =
          lastName[0].toUpperCase() + lastName.substring(1).toLowerCase();
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: GestureDetector(
          onLongPress: () async {
            String logs = await AuditLogger.readLogs();
            if (!context.mounted) return;
            _showAuditDialog(context, logs);
          },
          child: const Text("RECORD STEGANOGRAPHY"),
        ),
        actions: [
          // Logout Button: Clears session and returns to login
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout Session',
            onPressed: () => Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const LoginPage()),
            ),
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Welcome Message for Medical Personnel
            Text(
              "Welcome, $honorific $formattedLastName",
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.teal.shade800,
              ),
            ),
            const Text(
              "Authorized Clinical Session Active",
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 40),

            _buildMenuButton(context, "Conceal Patient Data", Icons.lock),
            const SizedBox(height: 20),
            _buildMenuButton(context, "Retrieve Patient Data", Icons.lock_open),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuButton(BuildContext context, String title, IconData icon) {
    return GestureDetector(
      onTap: () {
        if (title == "Conceal Patient Data") {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const ConcealPage()),
          );
        } else if (title == "Retrieve Patient Data") {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const RetrievePage()),
          );
        }
      },
      child: Container(
        width: 280, // Slightly wider for a professional look
        padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
        decoration: BoxDecoration(
          // 🎨 This replicates the "Import Records" Look
          color: Colors.teal.shade50.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.teal.shade100, width: 2),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.teal.shade700),
            const SizedBox(width: 15),
            Text(
              title,
              style: TextStyle(
                color: Colors.teal.shade800,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
