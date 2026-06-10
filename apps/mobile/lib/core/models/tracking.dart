// Guard presence / GPS-tracking value types. Pure (no Flutter) → unit-testable.

import 'geo.dart';

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

/// A guard's latest known position from `GET /v1/guards/{id}/location` (presence read API —
/// `contracts/openapi/presence.yaml` `GuardLocation`). The customer may read it only while
/// they have an active booking with that guard (server-enforced IDOR gate).
class GuardLocation {
  const GuardLocation({
    required this.guardId,
    required this.lat,
    required this.lng,
    required this.recordedAt,
    required this.isOnline,
    required this.isLive,
    this.accuracy,
    this.heading,
    this.speed,
  });

  final String guardId;
  final double lat;
  final double lng;

  /// Horizontal accuracy in metres (null when the platform didn't report it).
  final double? accuracy;

  /// Course over ground in degrees 0..360 (null when unknown) — rotates the marker.
  final double? heading;

  /// Speed in m/s (null when unknown).
  final double? speed;

  final DateTime recordedAt;

  /// A live WS session is currently connected for this guard.
  final bool isOnline;

  /// Server-computed freshness: `is_online AND recorded_at` within the last 5 minutes — the
  /// client renders staleness from THIS flag (no local clock math against server time).
  final bool isLive;

  GeoPoint get point => GeoPoint(lat, lng);

  factory GuardLocation.fromJson(Map<String, dynamic> json) => GuardLocation(
        guardId: json['guard_id'] as String,
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        accuracy: (json['accuracy'] as num?)?.toDouble(),
        heading: (json['heading'] as num?)?.toDouble(),
        speed: (json['speed'] as num?)?.toDouble(),
        recordedAt:
            DateTime.tryParse(json['recorded_at'] as String? ?? '')?.toUtc() ??
                DateTime.now().toUtc(),
        isOnline: json['is_online'] == true,
        isLive: json['is_live'] == true,
      );

  /// Parse a response body defensively; `null` when it is not a well-formed location.
  static GuardLocation? tryParse(Object? data) {
    if (data is! Map<String, dynamic>) return null;
    if (data['guard_id'] is! String ||
        data['lat'] is! num ||
        data['lng'] is! num) {
      return null;
    }
    return GuardLocation.fromJson(data);
  }
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
