import 'package:flutter/material.dart';

import '../core/payments/qr_encoder.dart';

/// Renders a QR payload as a scannable black-on-white square — no package, no network. Uses the
/// dependency-free [encodeQr] (the SAME byte-mode/level-M encoder the web-admin ships), so the
/// PromptPay `qr_payload` scans identically on web and mobile. A 4-module quiet zone (white border)
/// is baked in so the camera can lock onto the finder patterns.
class QrView extends StatelessWidget {
  const QrView({super.key, required this.data, this.size = 220});

  /// The string to encode (here: the server's authoritative EMVCo PromptPay payload).
  final String data;

  /// Rendered side length in logical pixels.
  final double size;

  @override
  Widget build(BuildContext context) {
    // Encoding is pure + fast for a ~100-char payload; a failure (e.g. an empty/over-long string)
    // degrades to a blank white square rather than crashing the pay screen.
    QrMatrix? qr;
    try {
      if (data.isNotEmpty) qr = encodeQr(data);
    } catch (_) {
      qr = null;
    }
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _QrPainter(qr)),
    );
  }
}

class _QrPainter extends CustomPainter {
  const _QrPainter(this.qr);

  final QrMatrix? qr;

  static const int _quiet = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final white = Paint()..color = Colors.white;
    canvas.drawRect(Offset.zero & size, white);
    final qr = this.qr;
    if (qr == null) return;

    final modules = qr.size + _quiet * 2;
    final cell = size.width / modules;
    final black = Paint()..color = Colors.black;
    for (var r = 0; r < qr.size; r++) {
      for (var c = 0; c < qr.size; c++) {
        if (!qr.matrix[r][c]) continue;
        // +1px on each side avoids hairline gaps between cells from float rounding.
        final left = (c + _quiet) * cell;
        final top = (r + _quiet) * cell;
        canvas.drawRect(
          Rect.fromLTWH(left, top, cell + 0.5, cell + 0.5),
          black,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_QrPainter old) => old.qr != qr;
}
