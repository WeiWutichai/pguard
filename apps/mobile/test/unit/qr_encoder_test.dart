import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/payments/qr_encoder.dart';

/// A deterministic signature of a QR matrix: the module count and a stable rolling hash of the
/// flattened "01" rows (`h = h*31 + char`, unsigned 32-bit). The SAME signature is computed by the
/// reference TS encoder (`apps/web-admin/src/components/ui/qr-code.tsx`) in node, so a match proves
/// this Dart port is byte-for-byte identical to the web encoder — the PromptPay `qr_payload` scans
/// the same on both clients.
({int size, int dark, int hash}) signature(QrMatrix qr) {
  var dark = 0;
  final buf = StringBuffer();
  for (var r = 0; r < qr.size; r++) {
    for (var c = 0; c < qr.size; c++) {
      if (qr.matrix[r][c]) {
        dark++;
        buf.write('1');
      } else {
        buf.write('0');
      }
    }
  }
  final flat = buf.toString();
  var h = 0;
  for (var i = 0; i < flat.length; i++) {
    h = (h * 31 + flat.codeUnitAt(i)) & 0xFFFFFFFF;
  }
  return (size: qr.size, dark: dark, hash: h);
}

void main() {
  // Reference signatures produced by running the web-admin's `encode()` (the SAME algorithm) over
  // the same inputs in node. A match = the Dart port reproduces the web encoder exactly.
  const promptpay =
      '00020101021229370016A00000067701011101130066812345678530376454072000.005802TH6304XXXX';

  test('matches the web encoder for a short payload (HELLO)', () {
    final s = signature(encodeQr('HELLO'));
    expect(s.size, 21, reason: 'version 1 → 21×21');
    expect(s.dark, 228);
    expect(s.hash, 1916153698);
  });

  test('matches the web encoder for HELLO WORLD', () {
    final s = signature(encodeQr('HELLO WORLD'));
    expect(s.size, 21);
    expect(s.dark, 232);
    expect(s.hash, 736296098);
  });

  test('matches the web encoder for a real EMVCo PromptPay payload', () {
    final s = signature(encodeQr(promptpay));
    // ~86 bytes → version 6 → 41×41.
    expect(s.size, 41);
    expect(s.dark, 827);
    expect(s.hash, 2557632589);
  });

  test('encoding is deterministic (stable across runs)', () {
    expect(signature(encodeQr(promptpay)), signature(encodeQr(promptpay)));
  });

  test('square matrix of the reported size, all four finder corners dark', () {
    final qr = encodeQr(promptpay);
    expect(qr.matrix.length, qr.size);
    expect(qr.matrix.every((row) => row.length == qr.size), isTrue);
    // Finder pattern top-left corner module is dark; so are the other two finders' corners.
    expect(qr.matrix[0][0], isTrue);
    expect(qr.matrix[0][qr.size - 7], isTrue);
    expect(qr.matrix[qr.size - 7][0], isTrue);
  });

  test('an over-long payload throws rather than producing a corrupt QR', () {
    expect(() => encodeQr('x' * 300), throwsArgumentError);
  });
}
