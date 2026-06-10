/// A guard's hourly check-in as returned by `POST /v1/bookings/{id}/progress-reports`
/// (and listed by `GET …/progress-reports`). `photoUrl` is a FRESH presigned GET URL
/// (TTL 1h) the server signs per read from the stored `photoKey` — never persist it.
///
/// Note the wire asymmetry: the REQUEST part is `accuracy` (metres) but the RESPONSE key is
/// `accuracy_m`. Pure data — no I/O. Decoded defensively (mirrors the other core models).
class ProgressReport {
  const ProgressReport({
    required this.id,
    required this.bookingId,
    required this.guardId,
    required this.hourNumber,
    required this.photoKey,
    required this.photoUrl,
    required this.createdAt,
    this.lat,
    this.lng,
    this.accuracyM,
    this.note,
  });

  final String id;
  final String bookingId;
  final String guardId;
  final int hourNumber;
  final String photoKey;
  final String photoUrl;
  final DateTime createdAt;
  final double? lat;
  final double? lng;
  final double? accuracyM;
  final String? note;

  factory ProgressReport.fromJson(Map<String, dynamic> json) => ProgressReport(
        id: json['id'] as String? ?? '',
        bookingId: json['booking_id'] as String? ?? '',
        guardId: json['guard_id'] as String? ?? '',
        hourNumber: (json['hour_number'] as num?)?.toInt() ?? 0,
        photoKey: json['photo_key'] as String? ?? '',
        photoUrl: json['photo_url'] as String? ?? '',
        lat: (json['lat'] as num?)?.toDouble(),
        lng: (json['lng'] as num?)?.toDouble(),
        accuracyM: (json['accuracy_m'] as num?)?.toDouble(),
        note: json['note'] as String?,
        createdAt:
            DateTime.tryParse(json['created_at'] as String? ?? '')?.toUtc() ??
                DateTime.now().toUtc(),
      );
}
