import '../models/chat.dart';

/// Picks an image/video and uploads it to a conversation (`POST /v1/attachments`, multipart),
/// returning the stored [Attachment] (with a fresh presigned URL) — or `null` if the user
/// cancelled or no picker is available. Abstracted (like `PhotoCaptureService`) so the chat
/// composer + controller are testable without the camera/gallery native channels, and so a
/// size/MIME rejection surfaces as a friendly error rather than a raw exception.
///
/// The backend enforces JPEG/PNG/WEBP ≤10MB and MP4/MOV ≤200MB by magic bytes; a rejected upload
/// throws (the composer shows a friendly message). On success the composer sends a WS message of
/// type `image`/`video` carrying the attachment id in `content`.
abstract class ChatAttachmentService {
  Future<Attachment?> pickAndUpload(String conversationId);
}

/// Offline-safe default: no image/file picker plugin is wired, so attachment upload is
/// unavailable and [pickAndUpload] returns `null` (the composer simply shows it as unavailable).
///
/// NATIVE DEPENDENCY (documented): a real implementation needs an image/video picker
/// (`image_picker`) + a multipart `POST /v1/attachments` (Dio `FormData`). Until that plugin is
/// wired this provider returns the unavailable default — mirroring `PhotoCaptureService` /
/// `CheckInService`. Tests override the provider with a fake that returns a canned [Attachment].
class UnavailableChatAttachmentService implements ChatAttachmentService {
  const UnavailableChatAttachmentService();

  @override
  Future<Attachment?> pickAndUpload(String conversationId) async => null;
}
