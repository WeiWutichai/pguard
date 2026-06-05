import '../media/photo_capture.dart';
import '../models/tracking.dart';
import 'api_exception.dart';

/// Submits a guard's hourly progress report (photo + GPS).
///
/// BACKEND DEPENDENCY (documented — does not exist yet): v2 booking exposes NO progress-report /
/// check-in endpoint and there is NO media-upload path anywhere on the gateway. This interface
/// codes against the agreed v1-derived contract so the moment the endpoint lands the flow works:
///
///   POST `/v1/bookings/{id}/progress-reports`  (multipart/form-data)
///   fields: `hour_number` (int), `message` (optional), `lat`/`lng`/`accuracy` (optional GPS),
///           `files` (the photo part(s))
///   → 200 with the created report.
///
/// The check-in scheduling/missed logic and capture flow are fully built and testable; only the
/// upload is pending backend.
abstract class CheckInService {
  Future<void> submit({
    required String bookingId,
    required int hourNumber,
    required CapturedPhoto photo,
    GpsSample? gps,
    String? note,
  });
}

/// Default impl: the endpoint isn't built, so submission fails with a clear, generic message.
/// Tests override this provider with a fake that records submissions.
class PendingCheckInService implements CheckInService {
  const PendingCheckInService();

  @override
  Future<void> submit({
    required String bookingId,
    required int hourNumber,
    required CapturedPhoto photo,
    GpsSample? gps,
    String? note,
  }) async {
    throw const ApiException(
      message:
          'การเช็คอินยังไม่เปิดให้บริการ / Check-in upload is not available yet',
      code: 'NOT_IMPLEMENTED',
    );
  }
}
