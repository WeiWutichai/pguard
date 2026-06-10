import 'package:flutter/material.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

/// A lightweight stylised "map" backdrop (grid + faux roads) in the brand palette — stands in
/// for tiled imagery without any network dependency or native map SDK. Shared by the booking
/// map picker and the customer live-map (one painter, no copy-paste).
class MapBackdropPainter extends CustomPainter {
  const MapBackdropPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = PgTokens.colorGreen50;
    canvas.drawRect(Offset.zero & size, bg);

    final grid = Paint()
      ..color = PgTokens.colorGreen100
      ..strokeWidth = 1;
    const step = 28.0;
    for (var x = 0.0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (var y = 0.0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    final road = Paint()
      ..color = PgTokens.colorGreen200
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(0, size.height * 0.7),
        Offset(size.width, size.height * 0.35), road);
    canvas.drawLine(Offset(size.width * 0.3, 0),
        Offset(size.width * 0.55, size.height), road);
  }

  @override
  bool shouldRepaint(covariant MapBackdropPainter oldDelegate) => false;
}
