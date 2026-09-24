import 'dart:io';
import 'dart:typed_data';
import 'package:gal/gal.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

class ResultPage extends StatelessWidget {
  final Uint8List imageBytes;
  final double mse;
  final double psnr;

  const ResultPage({
    super.key,
    required this.imageBytes,
    required this.mse,
    required this.psnr,
  });

  Future<void> _saveToGallery(BuildContext context) async {
    try {
      final String fileName =
          "Stego_Clinical_Record_${DateTime.now().millisecondsSinceEpoch}";
      await Gal.putImageBytes(
        imageBytes,
        album: 'CUSTECH Clinical Stego',
        name: fileName,
      );

      if (Platform.isAndroid) {
        final tempFile = File('${Directory.systemTemp.path}/$fileName.png');
        await tempFile.writeAsBytes(imageBytes);
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(tempFile.path)],
            text: 'Secure Clinical Stego-Image',
          ),
        );
      }

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Stego-image saved to device gallery"),
          backgroundColor: Colors.teal,
          duration: Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Gallery save failed. Try checking app permissions."),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  void _showMetrics(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Steganographic Security Analysis",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const Divider(),
            _metricTile(
              "Mean Squared Error (MSE)",
              mse.toStringAsFixed(5),
              "Goal: → 0",
            ),
            _metricTile(
              "Peak Signal-to-Noise Ratio (PSNR)",
              "${psnr.toStringAsFixed(2)} dB",
              "Goal: > 30 dB",
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _metricTile(String title, String value, String goal) {
    return ListTile(
      title: Text(title),
      trailing: Text(
        value,
        style: const TextStyle(
          color: Colors.teal,
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
      ),
      subtitle: Text(goal),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Concealment Success"),
        backgroundColor: Colors.teal.shade800,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(25),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 100),
              const SizedBox(height: 10),
              const Text(
                "Data successfully hidden in image.",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 30),

              // Preview of the Stego Image
              Container(
                height: 200,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: Colors.teal.shade100),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(15),
                  child: Image.memory(imageBytes, fit: BoxFit.cover),
                ),
              ),

              const SizedBox(height: 30),

              ElevatedButton.icon(
                onPressed: () => _showMetrics(context),
                icon: const Icon(Icons.security),
                label: const Text("View Security Metrics"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal.shade700,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(250, 50),
                ),
              ),

              const SizedBox(height: 15),

              ElevatedButton.icon(
                onPressed: () => _saveToGallery(context),
                icon: const Icon(Icons.download),
                label: const Text("Save to Gallery & Share"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey.shade800,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(250, 50),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
