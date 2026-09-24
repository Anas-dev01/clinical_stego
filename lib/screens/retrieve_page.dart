import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart' as material;
import 'package:flutter/material.dart' hide Image;
import 'package:file_picker/file_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:image/image.dart' as img;

import '../logic/security.dart';
import '../logic/lsb_engine.dart';
import '../logic/logger.dart';
import '../logic/cabinet_service.dart';
import 'result_page.dart'; // Added required import for the metrics page

class RetrievePage extends StatefulWidget {
  const RetrievePage({super.key});

  @override
  State<RetrievePage> createState() => _RetrievePageState();
}

class _RetrievePageState extends State<RetrievePage> {
  // Cabinet Search States
  final _searchController = TextEditingController();
  String? _patientFolderPath;
  List<File> _stegoFiles = [];
  File? _selectedStegoFile;

  // Security States
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  String? _decryptedRecord;
  bool _isLoading = false;

  int _failedAttempts = 0;
  DateTime? _lockoutUntil;
  int _secondsRemaining = 0;

  void _resetFields() {
    setState(() {
      _searchController.clear();
      _patientFolderPath = null;
      _stegoFiles = [];
      _selectedStegoFile = null;
      _passwordController.clear();
      _decryptedRecord = null;
      _failedAttempts = 0;
    });
  }

  void _startLockout(int seconds) {
    setState(() {
      _lockoutUntil = DateTime.now().add(Duration(seconds: seconds));
      _secondsRemaining = seconds;
    });
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      setState(() {
        _secondsRemaining = _lockoutUntil!.difference(DateTime.now()).inSeconds;
      });
      return _secondsRemaining > 0;
    });
  }

  // --- PHASE 1: TRACING THE PATIENT IN THE CABINET ---
  Future<void> _searchCabinet() async {
    String query = _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() => _isLoading = true);

    if (!mounted) return;
    var results = await CabinetService.searchPatient(query);
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (results.isEmpty) {
      _showStatus("Patient not found in local registry.", isError: true);
      setState(() {
        _patientFolderPath = null;
        _stegoFiles = [];
        _selectedStegoFile = null;
        _decryptedRecord = null;
      });
      return;
    }

    // IF EXACTLY ONE MATCH IS FOUND: Go straight to it
    if (results.length == 1) {
      _selectPatientFromSearch(results[0]);
    }
    // IF MULTIPLE MATCHES ARE FOUND: Show a selection list
    else {
      showDialog(
        context: context,
        builder: (context) => material.AlertDialog(
          title: const Text(
            "Multiple Patients Found",
            style: TextStyle(color: Colors.teal),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: results.length,
              itemBuilder: (context, index) {
                var patient = results[index];
                return ListTile(
                  leading: const Icon(Icons.folder_shared, color: Colors.teal),
                  title: Text(
                    patient['matric_number'],
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(patient['student_name']),
                  onTap: () {
                    Navigator.pop(context); // Close dialog
                    _selectPatientFromSearch(
                      patient,
                    ); // Load this specific patient
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("CANCEL"),
            ),
          ],
        ),
      );
    }
  }

  // Helper method to load the selected patient's folder
  void _selectPatientFromSearch(Map<String, dynamic> patient) async {
    setState(() => _isLoading = true);
    String folderPath = patient['folder_path'];
    await _loadFolderFiles(folderPath);

    setState(() {
      _patientFolderPath = folderPath;
      _isLoading = false;
    });

    if (_stegoFiles.isEmpty) {
      _showStatus(
        "Cabinet located, but no PNG record was found in this folder.",
        isError: true,
      );
    } else {
      _showStatus(
        "Cabinet Located: ${patient['student_name']}",
        isError: false,
      );
    }
  }

  Future<void> _loadFolderFiles(String folderPath) async {
    final dir = Directory(folderPath);
    if (await dir.exists()) {
      var files = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.png'))
          .toList();
      // Sort by newest first
      files.sort(
        (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
      );
      setState(() {
        _stegoFiles = files;
        _selectedStegoFile = files.isNotEmpty ? files.first : null;
        _decryptedRecord = null;
      });
    } else {
      setState(() {
        _stegoFiles = [];
        _selectedStegoFile = null;
        _decryptedRecord = null;
      });
    }
  }

  // --- PHASE 2: DECRYPTION ---
  void _processRetrieve() async {
    if (_lockoutUntil != null && DateTime.now().isBefore(_lockoutUntil!)) {
      _showStatus(
        "Security Lockout Active. Wait $_secondsRemaining seconds.",
        isError: true,
      );
      return;
    }

    if (_selectedStegoFile == null || _passwordController.text.isEmpty) {
      _showStatus("Select a file and enter passkey", isError: true);
      return;
    }

    setState(() => _isLoading = true);

    try {
      String? encryptedData = await LsbEngine.extractData(_selectedStegoFile!);

      if (encryptedData == null || !encryptedData.contains(':')) {
        _showStatus("No hidden clinical data detected", isError: true);
      } else {
        String? result = SecretCipher.decryptData(
          encryptedData,
          _passwordController.text,
        );

        if (result != null) {
          setState(() {
            _decryptedRecord = result;
            _failedAttempts = 0;
            _lockoutUntil = null;
          });
          await AuditLogger.logEvent(
            "RETRIEVED clinical history from ${_selectedStegoFile!.path.split('/').last}",
          );
          _showStatus("Decryption Successful", isError: false);
        } else {
          _failedAttempts++;
          await AuditLogger.logEvent(
            "FAILED decryption attempt #$_failedAttempts.",
          );
          if (_failedAttempts >= 3) {
            int delay = (_failedAttempts == 3)
                ? 30
                : (_failedAttempts == 4)
                ? 60
                : 300;
            _startLockout(delay);
            _showStatus(
              "AUTH ERROR: Brute-force detected. Lockout for $delay s",
              isError: true,
            );
          } else {
            _showStatus("AUTH ERROR: Invalid Passkey", isError: true);
          }
        }
      }
    } catch (e) {
      _showStatus("Retrieval Error: $e", isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- PHASE 3: THE UPDATE LOOP (NEW CONSULTATION) ---
  Future<void> _handleNewConsultation() async {
    final complaintCtrl = TextEditingController();
    final diagnosisCtrl = TextEditingController();
    final prescriptionCtrl = TextEditingController();

    // 1. Get the new diagnosis from the Doctor
    await showDialog(
      context: context,
      builder: (context) => material.AlertDialog(
        title: const Text(
          "Administer Treatment",
          style: TextStyle(color: Colors.teal),
        ),
        // Keeps the form and actions within the visible area when the
        // on-screen keyboard reduces the dialog's available height.
        scrollable: true,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: complaintCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: "Presenting Complaints",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: diagnosisCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: "Diagnosis / Clinical Finding",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: prescriptionCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: "Treatment / Prescription",
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("CANCEL"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal.shade800,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("PROCEED TO HIDE"),
          ),
        ],
      ),
    ).then((proceed) async {
      if (proceed != true ||
          complaintCtrl.text.isEmpty ||
          diagnosisCtrl.text.isEmpty) {
        return;
      }

      // 2. Require a FRESH cover image (Cryptographic rule!)
      FilePickerResult? imgResult = await FilePicker.platform.pickFiles(
        type: FileType.image,
      );
      if (imgResult == null) {
        _showStatus(
          "Action aborted: You must select a new cover image.",
          isError: true,
        );
        return;
      }
      File newCover = File(imgResult.files.single.path!);

      setState(() => _isLoading = true);

      try {
        // 3. Append the new data to the old decrypted record using the VISIT block format
        // This captures YYYY-MM-DD HH:MM (e.g., 2026-06-06 14:30)
        String dateStr = DateTime.now().toString().substring(0, 16);
        String newVisitBlock =
            ":::VISIT|$dateStr|${_cleanField(complaintCtrl.text)}|${_cleanField(diagnosisCtrl.text)}|${_cleanField(prescriptionCtrl.text)}";
        String updatedPayload = _decryptedRecord! + newVisitBlock;

        // 4. Encrypt and Embed
        String encryptedText = SecretCipher.encryptData(
          updatedPayload,
          _passwordController.text,
        );
        final Uint8List imageBytes = await newCover.readAsBytes();
        final img.Image? originalImage = img.decodeImage(imageBytes);
        if (originalImage == null) throw "Failed to decode cover image.";

        final img.Image stegoImage = LsbEngine.embedData(
          originalImage,
          encryptedText,
        );

        // NEW: Calculate the security metrics before saving!
        final metrics = LsbEngine.calculateMetrics(originalImage, stegoImage);

        // 5. Save to the Patient's Folder (Chronological Naming)
        String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
        String matric = _decryptedRecord!.split(":::")[1].split("|")[0];
        String outputPath =
            "$_patientFolderPath/Stego_${matric}_$timestamp.png";

        File resultFile = File(outputPath);
        final stegoBytes = Uint8List.fromList(img.encodePng(stegoImage));
        await resultFile.parent.create(recursive: true);
        await resultFile.writeAsBytes(stegoBytes);

        final savedPayload = await LsbEngine.extractData(resultFile);
        if (savedPayload != encryptedText) {
          throw "Saved image verification failed. Please select a clearer PNG cover image and try again.";
        }

        await AuditLogger.logEvent(
          "UPDATED clinical record for $matric. Saved as Stego_${matric}_$timestamp.png",
        );

        // 6. Push to the Result Page to show metrics!
        if (!mounted) return;

        // Notice the 'await' keyword added here!
        // This tells the app to wait until the ResultPage is closed.
        await Navigator.push(
          context,
          material.MaterialPageRoute(
            builder: (context) => ResultPage(
              imageBytes: stegoBytes,
              mse: metrics['mse']!,
              psnr: metrics['psnr']!,
            ),
          ),
        );

        // 7. SECURE RESET: Wipe all data when returning to the Retrieval Page
        if (mounted) {
          _resetFields();
          _showStatus("Session cleared for security.", isError: false);
        }
      } catch (e) {
        _showStatus("Update Failed: $e", isError: true);
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    });
  }

  void _showStatus(String msg, {required bool isError}) {
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.redAccent : Colors.teal.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _cleanField(String value) {
    return value
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll('|', '/')
        .replaceAll(':::', ' ');
  }

  // --- PDF LOGIC ---
  Future<void> _exportToPDF() async {
    if (_decryptedRecord == null) return;
    final pdf = pw.Document();
    List<String> sections = _decryptedRecord!.split(":::");
    List<String> headers = sections[0].split("|");
    List<String> values = sections[1].split("|");

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Header(
                level: 0,
                child: pw.Text(
                  "CLINICAL DATA RETRIEVAL REPORT",
                  style: pw.TextStyle(
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.teal,
                  ),
                ),
              ),
              pw.SizedBox(height: 10),
              pw.Text(
                "Base Registration Profile",
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 5),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey400),
                children: List.generate(headers.length, (index) {
                  return pw.TableRow(
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(5),
                        child: pw.Text(
                          headers[index].replaceAll('_', ' '),
                          style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 10,
                          ),
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(5),
                        child: pw.Text(
                          index < values.length ? values[index] : "N/A",
                          style: const pw.TextStyle(fontSize: 10),
                        ),
                      ),
                    ],
                  );
                }),
              ),
              pw.SizedBox(height: 20),

              if (sections.length > 2) ...[
                pw.Text(
                  "Medical History / Consultations",
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 5),
                ...sections.skip(2).map((visitBlock) {
                  var parts = visitBlock.split("|");
                  if (parts.length < 4) return pw.SizedBox();
                  final diagnosis = parts.length > 4 ? parts[3] : "";
                  final treatment = parts.length > 4 ? parts[4] : parts[3];
                  return pw.Container(
                    margin: const pw.EdgeInsets.only(bottom: 10),
                    padding: const pw.EdgeInsets.all(8),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.teal200),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          "Date: ${parts[1]}",
                          style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 10,
                          ),
                        ),
                        pw.Text(
                          "Complaints: ${parts[2]}",
                          style: const pw.TextStyle(fontSize: 10),
                        ),
                        if (diagnosis.isNotEmpty)
                          pw.Text(
                            "Diagnosis: $diagnosis",
                            style: const pw.TextStyle(fontSize: 10),
                          ),
                        pw.Text(
                          "Treatment: $treatment",
                          style: const pw.TextStyle(fontSize: 10),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ],
          );
        },
      ),
    );
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Clinical_Report.pdf',
    );
    await AuditLogger.logEvent(
      "EXPORTED Clinical Report for Patient ID: ${values[0]}",
    );
  }

  // --- UI BUILDERS ---
  Widget _buildClinicalDataView() {
    List<String> sections = _decryptedRecord!.split(":::");
    List<String> headers = sections[0].split("|");
    List<String> values = sections[1].split("|");

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Base Profile Table
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.teal.shade200),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Table(
            columnWidths: const {0: FlexColumnWidth(2), 1: FlexColumnWidth(3)},
            border: TableBorder.symmetric(
              inside: BorderSide(color: Colors.teal.shade100),
            ),
            children: List.generate(headers.length, (index) {
              return TableRow(
                decoration: BoxDecoration(
                  color: index % 2 == 0
                      ? Colors.white
                      : Colors.teal.withValues(alpha: 0.05),
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: Text(
                      headers[index].replaceAll('_', ' ').toUpperCase(),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                        color: Colors.teal,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: Text(
                      index < values.length ? values[index] : "N/A",
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              );
            }),
          ),
        ),
        const SizedBox(height: 20),

        // Medical History Blocks
        if (sections.length > 2) ...[
          const Text(
            "MEDICAL HISTORY",
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 10),
          ...sections.skip(2).map((visitBlock) {
            var parts = visitBlock.split(
              "|",
            ); // [VISIT, Date, Complaints, Prescription]
            if (parts.length < 4) return const SizedBox();
            final diagnosis = parts.length > 4 ? parts[3] : "";
            final treatment = parts.length > 4 ? parts[4] : parts[3];
            return Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                side: BorderSide(color: Colors.teal.shade100),
                borderRadius: BorderRadius.circular(8),
              ),
              margin: const EdgeInsets.only(bottom: 10),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ---> UPDATED DATE & TIME ROW <---
                    Row(
                      children: [
                        const Icon(
                          Icons.access_time,
                          size: 16,
                          color: Colors.teal,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          "Date & Time: ${parts[1]}",
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.teal,
                          ),
                        ),
                      ],
                    ),
                    const Divider(),
                    Text(
                      "Complaints:",
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(parts[2], style: const TextStyle(fontSize: 14)),
                    const SizedBox(height: 8),
                    if (diagnosis.isNotEmpty) ...[
                      Text(
                        "Diagnosis:",
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(diagnosis, style: const TextStyle(fontSize: 14)),
                      const SizedBox(height: 8),
                    ],
                    Text(
                      "Treatment / Prescription:",
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(treatment, style: const TextStyle(fontSize: 14)),
                  ],
                ),
              ),
            );
          }),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isLocked =
        _lockoutUntil != null && DateTime.now().isBefore(_lockoutUntil!);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("CLINICAL RETRIEVAL"),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.teal.shade800,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _resetFields),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // STEP 1: CABINET SEARCH
            const Text(
              "CABINET SEARCH",
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      labelText: "Enter Matric Number",
                      filled: true,
                      fillColor: Colors.grey.shade50,
                      prefixIcon: const Icon(Icons.search, color: Colors.teal),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal.shade700,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(60, 60),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _searchCabinet,
                  child: const Icon(Icons.manage_search),
                ),
              ],
            ),
            const SizedBox(height: 30),

            // STEP 2: PATIENT FILE TIMELINE
            if (_stegoFiles.isNotEmpty) ...[
              const Text(
                "PATIENT FOLDER (SELECT RECORD)",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                height: 120,
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.teal.shade100),
                ),
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.all(10),
                  itemCount: _stegoFiles.length,
                  itemBuilder: (context, index) {
                    File file = _stegoFiles[index];
                    bool isSelected = _selectedStegoFile?.path == file.path;
                    String dateLabel = file.lastModifiedSync().toString().split(
                      ' ',
                    )[0]; // Just the date
                    return GestureDetector(
                      onTap: () => setState(() {
                        _selectedStegoFile = file;
                        _decryptedRecord = null;
                      }),
                      child: Container(
                        width: 100,
                        margin: const EdgeInsets.only(right: 10),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: isSelected
                                ? Colors.teal
                                : Colors.transparent,
                            width: 3,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(5),
                              child: material.Image.file(
                                file,
                                fit: BoxFit.cover,
                              ),
                            ),
                            Positioned(
                              bottom: 0,
                              left: 0,
                              right: 0,
                              child: Container(
                                color: Colors.black54,
                                padding: const EdgeInsets.all(4),
                                child: Text(
                                  dateLabel,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 30),

              // STEP 3: AUTHENTICATION
              const Text(
                "AUTHENTICATION",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                enabled: !isLocked,
                decoration: InputDecoration(
                  labelText: isLocked ? "System Locked" : "Decryption Passkey",
                  filled: true,
                  fillColor: isLocked ? Colors.grey[100] : Colors.grey.shade50,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  prefixIcon: const Icon(
                    Icons.vpn_key_outlined,
                    color: Colors.teal,
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.teal),
                    )
                  : ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 60),
                        backgroundColor: isLocked
                            ? Colors.grey
                            : Colors.teal.shade800,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                      onPressed: isLocked ? null : _processRetrieve,
                      child: Text(
                        isLocked
                            ? "LOCKED ($_secondsRemaining s)"
                            : "EXTRACT & DECRYPT RECORD",
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
            ],

            // STEP 4: DECRYPTED DATA & UPDATE LOOP
            if (_decryptedRecord != null) ...[
              const SizedBox(height: 30),
              _buildClinicalDataView(),
              const SizedBox(height: 20),

              // NEW CONSULTATION LOOP BUTTON
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.shade700,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: _handleNewConsultation,
                icon: const Icon(Icons.add_comment),
                label: const Text("➕ ADD NEW CONSULTATION"),
              ),
              const SizedBox(height: 15),

              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal.shade800,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: _exportToPDF,
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text("GENERATE PDF REPORT"),
              ),
              const SizedBox(height: 30),
            ],
          ],
        ),
      ),
    );
  }
}
