// Guard presence / GPS-tracking value types. Pure (no Flutter) → unit-testable.

/// One GPS fix streamed while a guard is online. `accuracy` is the horizontal accuracy in
/// metres (null if the platform doesn't report it).
class GpsSample {
  const GpsSample({
    required this.lat,
    required this.lng,
    required this.recordedAt,
    this.accuracy,
  });

  final double lat;
  final double lng;
  final double? accuracy;
  final DateTime recordedAt;

  /// The presence WS frame shape (documented contract — see [PresenceSocket]).
  Map<String, dynamic> toFrame() => {
        'type': 'location',
        'lat': lat,
        'lng': lng,
        if (accuracy != null) 'accuracy': accuracy,
        'recorded_at': recordedAt.toUtc().toIso8601String(),
      };
}

/// Qualitative GPS accuracy band derived from the horizontal accuracy in metres — the design
/// shows a phrase ("แม่นยำสูง" / high) plus the numeric metres. Pure + testable.
enum GpsAccuracyBand {
  high('แม่นยำสูง', 'High'),
  medium('แม่นยำปานกลาง', 'Medium'),
  low('สัญญาณอ่อน', 'Weak'),
  unknown('ไม่มีสัญญาณ', 'No signal');

  const GpsAccuracyBand(this.labelTh, this.labelEn);

  final String labelTh;
  final String labelEn;

  /// <=10m high · <=30m medium · >30m low · null/negative unknown.
  static GpsAccuracyBand of(double? metres) {
    if (metres == null || metres < 0) return GpsAccuracyBand.unknown;
    if (metres <= 10) return GpsAccuracyBand.high;
    if (metres <= 30) return GpsAccuracyBand.medium;
    return GpsAccuracyBand.low;
  }
}
