import 'package:flutter_test/flutter_test.dart';

import 'package:clinical_stego/main.dart';

void main() {
  testWidgets('App opens to the staff login portal', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ClinicalStegoApp());

    expect(find.text('CLINICAL STAFF LOGIN'), findsOneWidget);
    expect(find.text('Username'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('RECORD STEGANOGRAPHY'), findsNothing);
  });
}
