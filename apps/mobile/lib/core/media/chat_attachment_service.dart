import 'package:dio/dio.dart';

import '../models/chat.dart';
import '../network/api_client.dart';
import '../network/api_exception.dart';
import 'chat_media_picker.dart';

/// Picks an image/video from [source] and uploads it to a conversation
/// (`POST /v1/attachments`, multipart `conversation_id` + `file`), returning the stored
/// [Attachment] (with a fresh presigned URL) — or `null` if the user cancelled the picker.
/// Abstracted (like `PhotoCaptureService`) so the chat composer + controller are testable
/// without the camera/gallery native channels, and so a size/MIME rejection surfaces as a
/// friendly [ApiException] rather than a raw exception.
///
/// The backend validates size first, then declared MIME AND magic bytes (JPEG/PNG/WEBP ≤10MB,
/// MP4/MOV ≤200MB); a rejected upload throws (the composer shows the message). On success the
/// composer sends a WS message of type `image`/`video` carrying the attachment id in `content`
/// — the presigned URL itself is NEVER persisted client-side (it expires in 1h; viewers
/// re-resolve via `GET /attachments/{id}`).
abstract class ChatAttachmentService {
  Future<Attachment?> pickAndUpload(
      String conversationId, ChatAttachmentSource source,
      {required bool isThai});
}

/// Production service: real picker (`image_picker` via [ChatMediaPicker]) + multipart upload
/// through the authenticated [PguardApi] Dio client.
class ApiChatAttachmentService implements ChatAttachmentService {
  const ApiChatAttachmentService({
    required PguardApi api,
    required ChatMediaPicker picker,
  })  : _api = api,
        _picker = picker;

  final PguardApi _api;
  final ChatMediaPicker _picker;

  @override
  Future<Attachment?> pickAndUpload(
      String conversationId, ChatAttachmentSource source,
      {required bool isThai}) async {
    final media = await _picker.pick(source);
    if (media == null) return null; // user cancelled — not an error

    final mime = media.mimeType;
    if (!ChatMime.isSupported(mime)) {
      // Fail fast client-side with the same outcome the server's MIME gate would produce.
      throw ApiException(
          message: isThai ? 'ชนิดไฟล์ไม่รองรับ' : 'Unsupported file type');
    }

    // Size guard BEFORE the network round-trip: the api-gateway edge body cap (12 MiB for
    // POST /attachments) 413s anything larger with a bare body, which the app would surface as a
    // generic "Request failed". A short phone video easily clears 12 MiB, so reject it here with a
    // clear, actionable message. (Images are picker-compressed and stay well under the cap.) See
    // [ChatUploadLimit] for the backend follow-up needed to lift this for the 200MB video path.
    if (ChatUploadLimit.exceeds(media.sizeBytes)) {
      final mb = (media.sizeBytes / (1024 * 1024)).toStringAsFixed(0);
      throw ApiException(
        message: isThai
            ? 'ไฟล์ใหญ่เกินไป ($mb MB) — ส่งได้ไม่เกิน ${ChatUploadLimit.maxMb} MB กรุณาเลือกวิดีโอที่สั้นลง'
            : 'File too large ($mb MB) — the limit is ${ChatUploadLimit.maxMb} MB. Pick a shorter video.',
      );
    }

    final form = FormData.fromMap({
      'conversation_id': conversationId,
      'file': await MultipartFile.fromFile(
        media.path,
        filename: media.path.split('/').last,
        contentType: DioMediaType.parse(mime!),
      ),
    });
    final data = await _api.post('/attachments', data: form);
    final attachment = data is Map<String, dynamic> ? data : null;
    if (attachment == null) {
      throw ApiException(
          message: isThai ? 'อัปโหลดไฟล์ไม่สำเร็จ' : 'Upload failed');
    }
    return Attachment.fromJson(attachment);
  }
}

/// Offline-safe fallback: no picker available, [pickAndUpload] resolves to `null` (the
/// composer treats it like a cancel). Tests override the provider with a fake instead.
class UnavailableChatAttachmentService implements ChatAttachmentService {
  const UnavailableChatAttachmentService();

  @override
  Future<Attachment?> pickAndUpload(
          String conversationId, ChatAttachmentSource source,
          {required bool isThai}) async =>
      null;
}
