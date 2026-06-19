import 'dart:io';

import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../network/api_exception.dart';
import '../providers.dart';
import 'locale_controller.dart';

part 'guard_avatar_controller.g.dart';

/// The logged-in guard's avatar (self-uploaded profile picture). `build()` resolves the guard id
/// from `/auth/me` (own-only path, not trusted from client) and fetches the current avatar URL
/// (404 → null = none yet). `upload()` multiparts a freshly-picked image to the own-only endpoint.
/// State is the presigned URL (`AsyncValue<String?>`); while uploading it stays loading-with-
/// previous so the header keeps showing the old image under a spinner. Mirrors the guard-documents
/// upload (magic-byte MIME so the declared Content-Type always matches the bytes).
@riverpod
class GuardAvatarController extends _$GuardAvatarController {
  bool _disposed = false;
  String? _guardId;

  @override
  Future<String?> build() async {
    ref.onDispose(() => _disposed = true);
    final api = ref.read(pguardApiProvider);
    final me = await api.get('/auth/me') as Map<String, dynamic>;
    final guardId = (me['user_id'] as String?) ?? (me['sub'] as String?) ?? '';
    if (guardId.isEmpty) {
      throw const ApiException(message: 'No guard session', statusCode: 401);
    }
    _guardId = guardId;
    // Probe the current avatar (404 → none). Best-effort: a read error → null (no fake image).
    try {
      final data = await api.get('/profile/guard/$guardId/avatar');
      return data is Map<String, dynamic>
          ? data['avatar_url'] as String?
          : null;
    } on ApiException {
      return null;
    }
  }

  /// Upload a freshly-picked image as the avatar (own-only multipart endpoint). Returns null on
  /// success, or a user-safe error message.
  Future<String?> upload(String filePath) async {
    final isThai = ref.read(localeControllerProvider) == AppLocale.th;
    final guardId = _guardId;
    if (guardId == null) return isThai ? 'ยังไม่พร้อม' : 'Not ready';

    final prev = state;
    // Keep the previous URL visible under a spinner while the upload is in flight.
    state = const AsyncLoading<String?>().copyWithPrevious(prev);

    final api = ref.read(pguardApiProvider);
    try {
      // Declare the MIME from the file's actual magic bytes (image_picker may re-encode to JPEG
      // while keeping the source extension), so the server's magic-byte gate always matches.
      final mime = _detectImageMime(await _readHead(filePath, 12)) ?? 'image/jpeg';
      final form = FormData.fromMap({
        'file': await MultipartFile.fromFile(
          filePath,
          filename: filePath.split('/').last,
          contentType: DioMediaType.parse(mime),
        ),
      });
      final data = await api.post('/profile/guard/$guardId/avatar', data: form);
      final url =
          data is Map<String, dynamic> ? data['avatar_url'] as String? : null;
      if (_disposed) return null;
      state = AsyncData(url);
      return null;
    } on ApiException catch (e) {
      if (!_disposed) state = AsyncData(prev.valueOrNull);
      return _friendlyError(e, isThai);
    } catch (_) {
      if (!_disposed) state = AsyncData(prev.valueOrNull);
      return isThai ? 'อัปโหลดไม่สำเร็จ' : 'Upload failed';
    }
  }

  /// Map the server's technical image rejections to a friendly bilingual message.
  static String _friendlyError(ApiException e, bool isThai) {
    final m = e.message.toLowerCase();
    if (m.contains('too large') || e.statusCode == 413) {
      return isThai ? 'รูปใหญ่เกินไป (สูงสุด 10MB)' : 'Image too large (max 10MB)';
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

  /// Read the first [n] bytes of [path] (enough for a magic-byte sniff) without loading the file.
  static Future<List<int>> _readHead(String path, int n) async {
    final f = await File(path).open();
    try {
      return await f.read(n);
    } finally {
      await f.close();
    }
  }

  /// Detect the image MIME from magic bytes — mirrors the server's `detect_image_mime`. Returns
  /// null for anything that isn't JPEG/PNG/WEBP. (Same logic as the guard-documents upload; a
  /// shared image-upload util is a small follow-up.)
  static String? _detectImageMime(List<int> b) {
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
        b[0] == 0x52 &&
        b[1] == 0x49 &&
        b[2] == 0x46 &&
        b[3] == 0x46 &&
        b[8] == 0x57 &&
        b[9] == 0x45 &&
        b[10] == 0x42 &&
        b[11] == 0x50) {
      return 'image/webp';
    }
    return null;
  }
}
