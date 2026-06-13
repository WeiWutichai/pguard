import 'package:dio/dio.dart';

import '../media/chat_media_picker.dart' show ChatMime;
import '../media/photo_capture.dart';
import '../models/progress_report.dart';
import '../models/tracking.dart';
import 'api_client.dart';
import 'api_exception.dart';

/// Submits a guard's hourly progress report (photo + optional GPS/note).
///
/// Wire contract (merged — `contracts/openapi/booking.yaml`):
///
///   POST `/v1/bookings/{id}/progress-reports`  (multipart/form-data)
///   parts: `hour_number` (int ≥1) · `photo` (a SINGLE image part — JPEG/PNG/WEBP ≤10MB,
///          its Content-Type must be the real MIME; the server magic-byte-verifies) ·
///          `lat`+`lng` (optional pair, double) · `accuracy` (optional, metres) ·
///          `note` (optional, ≤2000 chars — omitted entirely when empty)
///   → 200 `{ data: ProgressReport }` (the created report + a presigned `photo_url`, TTL 1h)
///
/// Server errors the flow distinguishes (see [ApiCheckInService]): **409** = either the hour
/// was already checked in (idempotent — absorbed as success) or it is too early for this hour;
/// **413** = the photo is too large; **403/404** = not this booking's assigned guard.
abstract class CheckInService {
  /// `hourNumber` is the SERVER `hour_number` (1-based) — the controller maps the UI's 0-based
  /// schedule slot onto it before calling. `isThai` selects the single language for the
  /// guard-facing error messages (the service has no Riverpod `ref`, so the controller — which
  /// does — reads the locale and passes it down).
  Future<void> submit({
    required String bookingId,
    required int hourNumber,
    required CapturedPhoto photo,
    required bool isThai,
    GpsSample? gps,
    String? note,
  });
}

/// Production [CheckInService]: a multipart upload through the authenticated [PguardApi] Dio
/// client (mirrors `ApiChatAttachmentService`). It maps the merged contract's transport-level
/// outcomes to friendly, single-language results so the controller/UI need no status-code
/// knowledge (the message language follows the caller's `isThai`):
///  - **409 `DUPLICATE_CHECK_IN`** (sub-code; legacy servers: message "already exists") → returns
///    normally (the hour is already recorded — an idempotent retry is a success, so the controller
///    marks the slot done; nothing is re-uploaded).
///  - **409 other** (too early / not started yet) → a "not time yet" [ApiException].
///  - **413** → a "photo too large" [ApiException].
///  - **403/404** → a "can't check in for this job" [ApiException].
///  - **network** (no status) → a retry-safe message (the server guards against orphaned
///    objects, so re-submitting after a network blip is safe).
class ApiCheckInService implements CheckInService {
  const ApiCheckInService({required PguardApi api}) : _api = api;

  final PguardApi _api;

  /// `note` over this length is rejected by the server (contract `maxLength: 2000`); trim
  /// client-side to the same ceiling so an over-long note never costs a round-trip.
  static const _maxNoteChars = 2000;

  @override
  Future<void> submit({
    required String bookingId,
    required int hourNumber,
    required CapturedPhoto photo,
    required bool isThai,
    GpsSample? gps,
    String? note,
  }) async {
    // Derive the declared Content-Type from the file extension (CapturedPhoto has no MIME).
    // Check-in is image-only — reject anything that isn't JPEG/PNG/WEBP (ChatMime also maps
    // video extensions) before spending an upload, with the same outcome the server would give.
    final mime = ChatMime.fromPath(photo.path);
    if (mime == null || !mime.startsWith('image/')) {
      throw ApiException(
        message: isThai
            ? 'รองรับเฉพาะรูปภาพ JPEG/PNG/WEBP'
            : 'Photo must be JPEG, PNG or WEBP',
      );
    }

    final trimmedNote = note?.trim();
    final form = FormData.fromMap({
      'hour_number': hourNumber.toString(),
      if (gps != null) 'lat': gps.lat.toString(),
      if (gps != null) 'lng': gps.lng.toString(),
      if (gps?.accuracy != null) 'accuracy': gps!.accuracy!.toString(),
      if (trimmedNote != null && trimmedNote.isNotEmpty)
        'note': trimmedNote.length > _maxNoteChars
            ? trimmedNote.substring(0, _maxNoteChars)
            : trimmedNote,
      'photo': await MultipartFile.fromFile(
        photo.path,
        filename: photo.path.split('/').last,
        contentType: DioMediaType.parse(mime),
      ),
    });

    final dynamic data;
    try {
      data =
          await _api.post('/bookings/$bookingId/progress-reports', data: form);
    } on ApiException catch (e) {
      // Idempotent retry: a 409 for an already-recorded hour is a SUCCESS — return so the
      // controller marks the slot done (nothing was re-uploaded; the server checks the
      // duplicate before the upload).
      if (_isDuplicateHour(e)) return;
      throw _friendly(e, isThai: isThai);
    }

    // Validate the 200 body is a well-formed report (fail loudly on a malformed success,
    // mirroring the chat upload's null-guard). This is NOT a transport error, so it stays
    // OUTSIDE the catch above — otherwise `_friendly` would mis-map it to the network message.
    // The parsed report isn't surfaced upward — the controller marks the slot done from the
    // hour it submitted (no refetch, no polling), and no current screen consumes the report —
    // but parsing keeps the contract honest + the model ready for a future customer view.
    if (data is! Map<String, dynamic>) {
      throw ApiException(
        message: isThai ? 'ส่งรายงานเช็คอินไม่สำเร็จ' : 'Check-in failed',
      );
    }
    ProgressReport.fromJson(data);
  }

  /// `true` for the absorbable 409 — the hour is already recorded.
  ///
  /// Primary signal is the machine-readable `error.code == 'DUPLICATE_CHECK_IN'` from the
  /// server envelope (contract: `POST /bookings/{id}/progress-reports` 409). The English
  /// substring match is a CROSS-VERSION FALLBACK only (a new app talking to an older
  /// booking service that still emits a plain `CONFLICT` with the "already exists" message)
  /// — it can be removed once every staging/prod booking service emits the sub-code.
  static bool _isDuplicateHour(ApiException e) {
    if (e.statusCode != 409) return false;
    if (e.code == 'DUPLICATE_CHECK_IN') return true;
    final msg = e.message.toLowerCase();
    return msg.contains('already exists') || msg.contains('duplicate');
  }

  /// Map a transport-level [ApiException] to a friendly one in the caller's single language.
  /// Duplicate-hour 409 is handled by the caller (absorbed) and never reaches here.
  ApiException _friendly(ApiException e, {required bool isThai}) {
    final status = e.statusCode;
    if (status == 409) {
      // The non-duplicate 409 is "hour N opens once N-1 hours have elapsed" (or not started).
      return ApiException(
        message: isThai
            ? 'ยังไม่ถึงเวลาเช็คอินรอบนี้ ลองใหม่อีกครั้งภายหลัง'
            : 'It is not time for this check-in yet — try again shortly',
        statusCode: 409,
      );
    }
    if (status == 413) {
      return ApiException(
        message: isThai
            ? 'รูปภาพใหญ่เกินไป ถ่ายใหม่อีกครั้ง'
            : 'Photo is too large — please retake it',
        statusCode: 413,
      );
    }
    if (status == 403 || status == 404) {
      return ApiException(
        message: isThai
            ? 'เช็คอินงานนี้ไม่ได้ (ไม่ใช่ผู้รับงาน)'
            : "You can't check in for this job",
        statusCode: status,
      );
    }
    if (e.isNetwork) {
      return ApiException(
        message: isThai
            ? 'เครือข่ายขัดข้อง ส่งใหม่ได้เลย'
            : 'Network problem — you can submit again',
      );
    }
    // 400 / other: surface the server's own (already-safe) message verbatim.
    return e;
  }
}
