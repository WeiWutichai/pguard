import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../network/api_client.dart';
import '../network/api_exception.dart';
import '../providers.dart';
import 'locale_controller.dart';

part 'guard_documents_controller.g.dart';

/// The six guard credential images an APPROVED, logged-in guard manages from their profile. The
/// wire [key] matches the `document_type` enum in `contracts/openapi/profile.yaml` exactly (a
/// drift-lock test asserts the set). Images are uploaded POST-APPROVAL because a pending guard
/// has no session token (login requires approval) and the single-use registration `profile_token`
/// authorizes only the one profile write — so registration merely *selects* these, never uploads.
enum GuardCredential {
  idCard('id_card', 'บัตรประชาชน', 'ID card'),
  securityLicense('security_license', 'ใบอนุญาต รปภ.', 'Security license'),
  trainingCert('training_cert', 'ใบรับรองการฝึก', 'Training certificate'),
  criminalCheck('criminal_check', 'ใบตรวจประวัติ', 'Criminal record check'),
  driverLicense('driver_license', 'ใบขับขี่', 'Driver license'),
  passbookPhoto('passbook_photo', 'หน้าสมุดบัญชี', 'Bank passbook');

  const GuardCredential(this.key, this.labelTh, this.labelEn);

  final String key;
  final String labelTh;
  final String labelEn;

  String label(bool isThai) => isThai ? labelTh : labelEn;
}

/// One credential's state on the documents screen.
class DocSlot {
  const DocSlot({
    required this.credential,
    this.uploaded = false,
    this.downloadUrl,
    this.busy = false,
    this.error,
  });

  final GuardCredential credential;

  /// Server truth from the load-time probe (`GET …/documents?document_type=`): an image is stored.
  final bool uploaded;

  /// Short-lived (~1h) presigned GET URL for the stored image — drives the thumbnail preview. The
  /// raw S3 key is never exposed by the server.
  final String? downloadUrl;

  /// An upload for this credential is in flight.
  final bool busy;

  /// The last user-safe error for this slot (cleared when the next upload starts).
  final String? error;

  DocSlot copyWith({
    bool? uploaded,
    String? downloadUrl,
    bool? busy,
    String? error,
    bool clearError = false,
  }) {
    return DocSlot(
      credential: credential,
      uploaded: uploaded ?? this.uploaded,
      downloadUrl: downloadUrl ?? this.downloadUrl,
      busy: busy ?? this.busy,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// The documents screen state: the guard's id (for the own-only upload path) + one slot per
/// credential, in [GuardCredential] order.
class GuardDocumentsState {
  const GuardDocumentsState({required this.guardId, required this.slots});

  final String guardId;
  final List<DocSlot> slots;

  DocSlot slotFor(GuardCredential c) =>
      slots.firstWhere((s) => s.credential == c);

  /// How many credentials have a stored image (drives the header progress line).
  int get uploadedCount => slots.where((s) => s.uploaded).length;

  GuardDocumentsState withSlot(DocSlot updated) => GuardDocumentsState(
        guardId: guardId,
        slots: [
          for (final s in slots)
            s.credential == updated.credential ? updated : s,
        ],
      );
}

/// Drives the post-approval guard-documents screen: probes which credential images are already
/// stored (one-shot, NO polling) and uploads a freshly-picked image to the dedicated own-only
/// multipart endpoint.
///
/// Expiry dates are intentionally NOT edited here. They are captured once at registration (folded
/// into the single profile submit, which carries the full account number). The expiry itself lives
/// in a SEPARATE table (`profile.document_expiry`) and never touches `guard_profiles`. The reason
/// post-approval editing is deferred is only that no expiry-only endpoint is exposed yet: the one
/// current write path is `POST/PUT /profile/guard`, which does a NON-coalescing column overwrite
/// and reads `account_number` back masked, so round-tripping the profile to set an expiry would
/// corrupt the bank account. The safe follow-up is a dedicated endpoint over the already-existing
/// `repo::upsert_document_expiry` (which writes only `document_expiry`, never the bank fields).
@riverpod
class GuardDocumentsController extends _$GuardDocumentsController {
  bool _disposed = false;

  @override
  Future<GuardDocumentsState> build() async {
    ref.onDispose(() => _disposed = true);
    final api = ref.read(pguardApiProvider);
    // The upload/read endpoints are own-only: `{user_id}` must equal the caller. Resolve it from
    // the session (mirror ProfileController's `/auth/me`) rather than trust any client-held value.
    final me = await api.get('/auth/me') as Map<String, dynamic>;
    final guardId = (me['user_id'] as String?) ?? (me['sub'] as String?) ?? '';
    if (guardId.isEmpty) {
      final isThai = ref.read(localeControllerProvider) == AppLocale.th;
      throw ApiException(
        message: isThai ? 'ไม่พบเซสชันผู้ใช้' : 'No active session',
        statusCode: 401,
      );
    }
    // Probe each credential's server-side presence concurrently. Best-effort per slot — a 404
    // (not uploaded) or a transient read error resolves THAT slot to "not uploaded" and never
    // fails the whole load. One-shot: there is NO polling.
    final slots = await Future.wait([
      for (final c in GuardCredential.values) _probe(api, guardId, c),
    ]);
    return GuardDocumentsState(guardId: guardId, slots: slots);
  }

  Future<DocSlot> _probe(
      PguardApi api, String guardId, GuardCredential c) async {
    try {
      final data = await api.get(
        '/profile/guard/$guardId/documents',
        query: {'document_type': c.key},
      );
      final url =
          data is Map<String, dynamic> ? data['download_url'] as String? : null;
      return DocSlot(credential: c, uploaded: url != null, downloadUrl: url);
    } on ApiException {
      // 404 (valid type, not uploaded) or a transient read error → honest "not uploaded", never
      // a fabricated stored state.
      return DocSlot(credential: c);
    }
  }

  /// Upload a freshly-picked image for [credential] to the own-only endpoint
  /// (`POST /profile/guard/{guardId}/documents`, multipart). Returns null on success, or a
  /// user-safe error message. Re-uploading replaces the stored image.
  Future<String?> upload(GuardCredential credential, String filePath) async {
    final isThai = ref.read(localeControllerProvider) == AppLocale.th;
    final current = state.valueOrNull;
    if (current == null) {
      return isThai ? 'ยังไม่พร้อม' : 'Not ready';
    }
    if (current.slotFor(credential).busy) return null; // ignore a double-tap
    _patchSlot(credential, (s) => s.copyWith(busy: true, clearError: true));

    final api = ref.read(pguardApiProvider);
    try {
      // The server magic-byte-validates AND requires the declared MIME to match the bytes. The
      // file extension is NOT reliable (image_picker may re-encode to JPEG while keeping a .png/
      // .webp name), so declare from the ACTUAL magic bytes; default to JPEG and let the server
      // reject a non-image (surfaced as a friendly message below).
      final mime = detectImageMime(await _readFileHead(filePath, 12)) ?? 'image/jpeg';
      final form = FormData.fromMap({
        'document_type': credential.key,
        'file': await MultipartFile.fromFile(
          filePath,
          filename: filePath.split('/').last,
          contentType: DioMediaType.parse(mime),
        ),
      });
      final data = await api
          .post('/profile/guard/${current.guardId}/documents', data: form);
      final url =
          data is Map<String, dynamic> ? data['download_url'] as String? : null;
      _patchSlot(
        credential,
        (s) => s.copyWith(
          uploaded: true,
          downloadUrl: url,
          busy: false,
          clearError: true,
        ),
      );
      return null;
    } on ApiException catch (e) {
      final msg = _friendlyUploadError(e, isThai);
      _patchSlot(credential, (s) => s.copyWith(busy: false, error: msg));
      return msg;
    } catch (_) {
      final msg = isThai ? 'อัปโหลดไม่สำเร็จ' : 'Upload failed';
      _patchSlot(credential, (s) => s.copyWith(busy: false, error: msg));
      return msg;
    }
  }

  /// Map the server's (English, technical) document-upload rejections to a friendly bilingual
  /// message; other messages pass through. Keeps the wire contract authoritative server-side while
  /// the guard sees actionable TH/EN text.
  static String _friendlyUploadError(ApiException e, bool isThai) {
    final m = e.message.toLowerCase();
    if (m.contains('too large') || e.statusCode == 413) {
      return isThai ? 'ไฟล์ใหญ่เกินไป (สูงสุด 10MB)' : 'Image too large (max 10MB)';
    }
    if (m.contains('mime') ||
        m.contains('does not match') ||
        m.contains('unsupported')) {
      return isThai
          ? 'รองรับเฉพาะรูป JPEG, PNG หรือ WEBP'
          : 'Only JPEG, PNG or WEBP images are supported';
    }
    return e.message;
  }

  /// Update ONE slot against the LATEST state (so two concurrent uploads of different credentials
  /// don't clobber each other) and never write after the controller was disposed (the screen may
  /// pop mid-upload).
  void _patchSlot(GuardCredential c, DocSlot Function(DocSlot) update) {
    if (_disposed) return;
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(current.withSlot(update(current.slotFor(c))));
  }

  /// Read the first [n] bytes of [path] (enough for an image magic-byte sniff) without loading the
  /// whole file into memory.
  static Future<List<int>> _readFileHead(String path, int n) async {
    final f = await File(path).open();
    try {
      return await f.read(n);
    } finally {
      await f.close();
    }
  }

  /// Detect the image MIME from magic bytes — mirrors the server's `detect_image_mime`
  /// (services/profile/src/domain/documents.rs) so the declared Content-Type ALWAYS matches the
  /// actual content (image_picker can re-encode to JPEG while keeping the source extension, so the
  /// extension can't be trusted). Returns null for anything that isn't JPEG/PNG/WEBP. Pure →
  /// unit-tested.
  @visibleForTesting
  static String? detectImageMime(List<int> b) {
    if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) {
      return 'image/jpeg';
    }
    if (b.length >= 8 &&
        b[0] == 0x89 &&
        b[1] == 0x50 &&
        b[2] == 0x4E &&
        b[3] == 0x47 &&
        b[4] == 0x0D &&
        b[5] == 0x0A &&
        b[6] == 0x1A &&
        b[7] == 0x0A) {
      return 'image/png';
    }
    if (b.length >= 12 &&
        b[0] == 0x52 && // R
        b[1] == 0x49 && // I
        b[2] == 0x46 && // F
        b[3] == 0x46 && // F
        b[8] == 0x57 && // W
        b[9] == 0x45 && // E
        b[10] == 0x42 && // B
        b[11] == 0x50) {
      // P
      return 'image/webp';
    }
    return null;
  }
}
