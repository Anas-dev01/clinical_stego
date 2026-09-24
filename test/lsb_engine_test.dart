import 'dart:io';

import 'package:clinical_stego/logic/lsb_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test('LSB engine survives PNG save and reload', () async {
    final original = img.Image(width: 160, height: 160);
    img.fill(original, color: img.ColorRgb8(120, 160, 200));

    const payload = 'abc123def456:encryptedPayload';
    final stego = LsbEngine.embedData(original, payload);

    final file = File(
      '${Directory.systemTemp.path}/clinical_stego_lsb_test.png',
    );
    await file.writeAsBytes(img.encodePng(stego));

    final extracted = await LsbEngine.extractData(file);

    expect(extracted, payload);
  });
}
