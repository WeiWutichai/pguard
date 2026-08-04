import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/features/legal/terms_screen.dart';

/// The bundled document is a REAL asset: if it is dropped from pubspec or emptied, the registration
/// gate would have nothing to show. A plain (non-widget) test so the load runs on the real clock.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the terms asset is bundled and carries the document', () async {
    final text = await rootBundle.loadString(kTermsAsset);
    expect(text.trim(), isNotEmpty);
    expect(text, contains('PGUARD'));
    // A few clause markers — proof it is the document, not a placeholder.
    expect(text, contains('ข้อกำหนดและเงื่อนไขการใช้บริการ'));
    expect(text, contains('ข้อมูลส่วนบุคคล'));
  });
}
