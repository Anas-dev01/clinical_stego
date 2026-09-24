import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart' as material;
import 'package:flutter/material.dart' hide Image;
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'package:gal/gal.dart';
import 'package:image/image.dart' as img;

import '../logic/security.dart';
import '../logic/lsb_engine.dart';
import '../logic/logger.dart';
import '../logic/cabinet_service.dart'; // OUR NEW CABINET SERVICE
import 'result_page.dart';

class ConcealPage extends StatefulWidget {
  const ConcealPage({super.key});

  @override
  State<ConcealPage> createState() => _ConcealPageState();
}

class _ConcealPageState extends State<ConcealPage> {
  // Mode Toggle
  bool _isManualEntry = true;

  // File & Image States
  File? _coverImage;
  List<List<dynamic>> _csvData = [];
  String? _selectedPatientID;
  String? _patientRecordString;

  // Manual Entry Controllers
  final _nameCtrl = TextEditingController();
  final _matricCtrl = TextEditingController();
  final _deptCtrl = TextEditingController();
  final _ageCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _complaintCtrl = TextEditingController();
  final _diagnosisCtrl = TextEditingController();
  final _prescriptionCtrl = TextEditingController();
  String? _gender;
  String? _bloodGroup;

  // Security Controllers
  final _passwordController = TextEditingController();
  final _filenameController = TextEditingController();

  bool _obscurePassword = true;
  bool _isPasswordStrong = false;
  bool _isLoading = false;
  bool _saveToGallery = true;

  bool _hasUpper = false;
  bool _hasLower = false;
  bool _hasNumber = false;
  bool _hasSpecial = false;
  bool _hasMinLength = false;

  void _resetFields() {
    setState(() {
      _coverImage = null;
      _selectedPatientID = null;
      _patientRecordString = null;
      _passwordController.clear();
      _filenameController.clear();
      _nameCtrl.clear();
      _matricCtrl.clear();
      _deptCtrl.clear();
      _ageCtrl.clear();
      _phoneCtrl.clear();
      _complaintCtrl.clear();
      _diagnosisCtrl.clear();
      _prescriptionCtrl.clear();
      _gender = null;
      _bloodGroup = null;
      _isPasswordStrong = false;
      _hasUpper = false;
      _hasLower = false;
      _hasNumber = false;
      _hasSpecial = false;
      _hasMinLength = false;
    });
  }

  String _cleanField(String value) {
    return value
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll('|', '/')
        .replaceAll(':::', ' ');
  }

  void _checkPasswordStrength(String value) {
    setState(() {
      _hasUpper = value.contains(RegExp(r'[A-Z]'));
      _hasLower = value.contains(RegExp(r'[a-z]'));
      _hasNumber = value.contains(RegExp(r'[0-9]'));
      _hasSpecial = value.contains(RegExp(r'[!@#\$&*~]'));
      _hasMinLength = value.length >= 8;
      _isPasswordStrong =
          _hasUpper && _hasLower && _hasNumber && _hasSpecial && _hasMinLength;
    });
  }

  Widget _buildRequirement(String label, bool isMet) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(
            isMet ? Icons.check_circle : Icons.radio_button_unchecked,
            color: isMet ? Colors.green : Colors.grey,
            size: 16,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: isMet ? Colors.green : Colors.grey.shade600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  // --- CSV LOGIC ---
  Future<void> _loadCSV() async {
    try {
      _showStatus("Opening File Picker...", isError: false);
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        withData: true,
      );
      if (result == null) return;

      final bytes = result.files.single.bytes;
      String rawContent = bytes != null
          ? utf8.decode(bytes)
          : await File(result.files.single.path!).readAsString();

      String standardizedContent = rawContent
          .replaceFirst('\ufeff', '')
          .replaceAll('\r\n', '\n')
          .replaceAll('\r', '\n')
          .trim();
      List<List<dynamic>> rows = const CsvToListConverter(
        eol: '\n',
        shouldParseNumbers: false,
      ).convert(standardizedContent);

      if (rows.isEmpty) throw "File is empty";
      if (rows[0][0].toString().trim() == 'Clinical_ID') {
        setState(() {
          _csvData = rows;
          _selectedPatientID = null;
        });
        _showStatus(
          "Success: ${rows.length - 1} records loaded",
          isError: false,
        );
      } else {
        throw "Header Mismatch: Expected 'Clinical_ID'";
      }
    } catch (e) {
      _showStatus("System Error: $e", isError: true);
    }
  }

  Future<void> _pickImage() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.image,
    );
    if (result != null) {
      setState(() => _coverImage = File(result.files.single.path!));
    }
  }

  // --- THE MASTER PIPELINE ---
  void _processConceal() async {
    // 1. Pre-Check
    if (_coverImage == null || !_isPasswordStrong) {
      _showStatus("Incomplete fields or weak passkey", isError: true);
      return;
    }

    String matric = "";
    String name = "";
    String dept = "";
    String payloadString = "";

    // 2. Format Data based on Mode
    if (_isManualEntry) {
      if (_nameCtrl.text.isEmpty ||
          _matricCtrl.text.isEmpty ||
          _complaintCtrl.text.isEmpty ||
          _diagnosisCtrl.text.isEmpty ||
          _gender == null) {
        _showStatus("Please fill all required manual fields.", isError: true);
        return;
      }
      matric = _matricCtrl.text.trim().toUpperCase();
      name = _cleanField(_nameCtrl.text);
      dept = _cleanField(_deptCtrl.text);

      String header =
          "Clinical_ID|Student_Name|Department|Age|Gender|Blood_Group|Phone|Date_Registered";
      String dateTimeStr = DateTime.now().toString().substring(0, 16);
      String values =
          "$matric|$name|$dept|${_cleanField(_ageCtrl.text)}|$_gender|${_bloodGroup ?? 'N/A'}|${_cleanField(_phoneCtrl.text)}|$dateTimeStr";
      String firstVisit =
          "VISIT|$dateTimeStr|${_cleanField(_complaintCtrl.text)}|${_cleanField(_diagnosisCtrl.text)}|${_cleanField(_prescriptionCtrl.text)}";

      payloadString = "$header:::$values:::$firstVisit";
    } else {
      if (_selectedPatientID == null) {
        _showStatus("Select a patient from the CSV.", isError: true);
        return;
      }
      matric = _selectedPatientID!;
      var rowData = _csvData.firstWhere(
        (r) => r[0].toString().trim() == matric,
      );
      name = rowData.length > 1 ? rowData[1].toString() : "Unknown";
      dept = rowData.length > 2 ? rowData[2].toString() : "Unknown";
      payloadString = _patientRecordString!;
    }

    setState(() => _isLoading = true);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const material.AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: material.Colors.teal),
            SizedBox(height: 20),
            Text(
              "Encoding Record & Routing to Cabinet...",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );

    try {
      // 3. Cabinet Database Routing (The Supervisor's Core Requirement)
      String targetFolder = "";
      var existingRecord = await CabinetService.findPatientByMatric(matric);

      if (existingRecord != null) {
        targetFolder =
            existingRecord['folder_path']; // Student exists, use their folder
      } else {
        var regResult = await CabinetService.registerStudent(
          matricNumber: matric,
          name: name,
          department: dept,
        );
        if (regResult['success'] == true) {
          targetFolder =
              regResult['folderPath']; // New student, grab the newly created folder
        } else {
          throw "Database Error: Could not verify patient directory.";
        }
      }

      // 4. Encrypt & Embed
      String encryptedText = SecretCipher.encryptData(
        payloadString,
        _passwordController.text,
      );
      final Uint8List imageBytes = await _coverImage!.readAsBytes();
      final img.Image? originalImage = img.decodeImage(imageBytes);
      if (originalImage == null) throw "Failed to decode cover image.";

      final img.Image stegoImage = LsbEngine.embedData(
        originalImage,
        encryptedText,
      );
      final metrics = LsbEngine.calculateMetrics(originalImage, stegoImage);
      final Uint8List stegoBytes = Uint8List.fromList(
        img.encodePng(stegoImage),
      );

      // 5. Save STRICTLY to the Cabinet Folder (No more random Gallery dumps)
      String customName = _filenameController.text.trim().replaceAll(
        RegExp(r'[^\w\s-]'),
        '',
      );
      if (customName.isEmpty) {
        customName = "Stego_${matric}_${DateTime.now().millisecondsSinceEpoch}";
      }
      final String outputPath = "$targetFolder/$customName.png";
      final File resultFile = File(outputPath);
      await resultFile.parent.create(recursive: true);
      await resultFile.writeAsBytes(stegoBytes);

      final savedPayload = await LsbEngine.extractData(resultFile);
      if (savedPayload != encryptedText) {
        throw "Saved image verification failed. Please select a clearer PNG cover image and try again.";
      }

      if (_saveToGallery) {
        try {
          await Gal.putImageBytes(
            stegoBytes,
            album: 'CUSTECH Clinical Stego',
            name: customName,
          );
        } catch (e) {
          await AuditLogger.logEvent("GALLERY SAVE FAILED for $matric: $e");
        }
      }

      // 6. Security Log
      await AuditLogger.logEvent(
        "SECURED clinical record for Patient ID: $matric. Saved strictly to $outputPath",
      );

      if (!mounted) return;
      Navigator.pop(context); // Close dialog

      // 7. Success!
      Navigator.push(
        context,
        material.MaterialPageRoute(
          builder: (context) => ResultPage(
            imageBytes: stegoBytes,
            mse: metrics['mse']!,
            psnr: metrics['psnr']!,
          ),
        ),
      );
      _resetFields();
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _showStatus("Concealment Failed: $e", isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showStatus(String msg, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: Colors.white,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                msg,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        backgroundColor: isError ? Colors.redAccent : Colors.teal.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // --- UI BUILDERS ---
  Widget _buildManualEntryForm() {
    return Column(
      children: [
        TextField(
          controller: _matricCtrl,
          decoration: const InputDecoration(
            labelText: "Matric Number (Clinical ID)*",
            prefixIcon: Icon(Icons.badge),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _nameCtrl,
          decoration: const InputDecoration(
            labelText: "Full Student Name*",
            prefixIcon: Icon(Icons.person),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _deptCtrl,
          decoration: const InputDecoration(
            labelText: "Department",
            prefixIcon: Icon(Icons.school),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _ageCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: "Age",
                  prefixIcon: Icon(Icons.cake),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: "Phone",
                  prefixIcon: Icon(Icons.phone),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                decoration: const InputDecoration(
                  labelText: "Gender*",
                  prefixIcon: Icon(Icons.wc),
                ),
                items: ['Male', 'Female']
                    .map(
                      (String val) =>
                          DropdownMenuItem(value: val, child: Text(val)),
                    )
                    .toList(),
                onChanged: (val) => setState(() => _gender = val),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButtonFormField<String>(
                decoration: const InputDecoration(
                  labelText: "Blood Group",
                  prefixIcon: Icon(Icons.bloodtype),
                ),
                items: ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-']
                    .map(
                      (String val) =>
                          DropdownMenuItem(value: val, child: Text(val)),
                    )
                    .toList(),
                onChanged: (val) => setState(() => _bloodGroup = val),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _complaintCtrl,
          minLines: 2,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: "Presenting Complaint*",
            prefixIcon: Icon(Icons.sick_outlined),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _diagnosisCtrl,
          minLines: 2,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: "Diagnosis / Clinical Finding*",
            prefixIcon: Icon(Icons.medical_information_outlined),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _prescriptionCtrl,
          minLines: 2,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: "Treatment / Prescription",
            prefixIcon: Icon(Icons.medication_outlined),
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
  }

  Widget _buildCSVImportForm() {
    return Column(
      children: [
        TextButton.icon(
          onPressed: _loadCSV,
          icon: const Icon(Icons.file_download_outlined, color: Colors.teal),
          label: Text(
            _csvData.isEmpty ? "Import Records CSV" : "Change Record (CSV)",
            style: const TextStyle(
              color: Colors.teal,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        if (_csvData.isNotEmpty)
          const Divider(color: Colors.teal, thickness: 0.5),
        if (_csvData.isNotEmpty)
          Row(
            children: [
              const Icon(Icons.badge_outlined, color: Colors.teal),
              const SizedBox(width: 15),
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    hint: const Text("Select Clinical ID"),
                    value: _selectedPatientID,
                    items: _csvData.skip(1).map((row) {
                      String id = row[0].toString().trim();
                      return DropdownMenuItem<String>(
                        value: id,
                        child: Text(id),
                      );
                    }).toList(),
                    onChanged: (val) {
                      setState(() {
                        _selectedPatientID = val;
                        var headerRow = _csvData[0]
                            .map((e) => e.toString().trim())
                            .join("|");
                        var rowData = _csvData.firstWhere(
                          (r) => r[0].toString().trim() == val,
                        );
                        var patientRow = rowData
                            .map((e) => e.toString().trim())
                            .join("|");
                        _patientRecordString = "$headerRow:::$patientRow";
                      });
                    },
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("RECORD CONCEALMENT"),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.teal.shade800,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // THE NEW TOGGLE SWITCH
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isManualEntry
                          ? Colors.teal.shade700
                          : Colors.grey.shade200,
                      foregroundColor: _isManualEntry
                          ? Colors.white
                          : Colors.black54,
                    ),
                    onPressed: () => setState(() => _isManualEntry = true),
                    child: const Text("Manual Entry"),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: !_isManualEntry
                          ? Colors.teal.shade700
                          : Colors.grey.shade200,
                      foregroundColor: !_isManualEntry
                          ? Colors.white
                          : Colors.black54,
                    ),
                    onPressed: () => setState(() => _isManualEntry = false),
                    child: const Text("CSV Import"),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // DYNAMIC INPUT AREA
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.teal.shade100, width: 2),
                color: Colors.teal.shade50.withValues(alpha: 0.3),
              ),
              child: _isManualEntry
                  ? _buildManualEntryForm()
                  : _buildCSVImportForm(),
            ),

            const SizedBox(height: 30),
            const Text(
              "COVER MEDICAL IMAGE",
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: _pickImage,
              child: Container(
                height: 220,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: _coverImage == null
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.add_photo_alternate_outlined,
                            color: Colors.grey.shade400,
                            size: 50,
                          ),
                          const Text(
                            "Select Lossless Image",
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      )
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: material.Image.file(
                          _coverImage!,
                          fit: BoxFit.cover,
                        ),
                      ),
              ),
            ),

            const SizedBox(height: 30),
            const Text(
              "SECURITY AUTHENTICATION",
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              onChanged: _checkPasswordStrength,
              decoration: InputDecoration(
                labelText: "Privacy Passkey",
                filled: true,
                fillColor: Colors.grey.shade50,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                prefixIcon: const Icon(Icons.lock_outline, color: Colors.teal),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility_off : Icons.visibility,
                    color: Colors.grey,
                  ),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Password Requirements:",
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 5),
                  _buildRequirement("At least 8 characters", _hasMinLength),
                  _buildRequirement(
                    "Uppercase & Lowercase letters",
                    _hasUpper && _hasLower,
                  ),
                  _buildRequirement("Numeric digit (0-9)", _hasNumber),
                  _buildRequirement("Special character (!@#\$&*)", _hasSpecial),
                ],
              ),
            ),

            const SizedBox(height: 30),
            const Text(
              "OUTPUT FILENAME",
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _filenameController,
              decoration: InputDecoration(
                labelText: "Stego-Image Name (Optional)",
                hintText: "e.g. Stego_Patient_Visit_1",
                filled: true,
                fillColor: Colors.grey.shade50,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                prefixIcon: const Icon(Icons.edit_note, color: Colors.teal),
              ),
            ),
            const SizedBox(height: 10),
            SwitchListTile(
              value: _saveToGallery,
              contentPadding: EdgeInsets.zero,
              activeThumbColor: Colors.teal.shade700,
              title: const Text("Save copy to device gallery"),
              secondary: const Icon(
                Icons.photo_library_outlined,
                color: Colors.teal,
              ),
              onChanged: (value) => setState(() => _saveToGallery = value),
            ),

            const SizedBox(height: 40),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 60),
                backgroundColor: Colors.teal.shade800,
                disabledBackgroundColor: Colors.grey.shade300,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                elevation: 5,
              ),
              onPressed:
                  (_coverImage != null && _isPasswordStrong && !_isLoading)
                  ? _processConceal
                  : null,
              child: const Text(
                "GENERATE & FILE STEGO-IMAGE",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
