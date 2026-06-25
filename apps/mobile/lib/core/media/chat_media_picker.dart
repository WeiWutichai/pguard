import 'package:image_picker/image_picker.dart';

/// Where a chat attachment comes from (the composer's source sheet).
enum ChatAttachmentSource { cameraPhoto, galleryPhoto, galleryVideo }

/// A picked media file, ready to upload. [mimeType] may be null when neither the platform nor
/// the file extension could identify it (the upload service rejects it with a friendly error
/// rather than letting the server's magic-byte check fail later). [sizeBytes] is the on-disk
/// length, used to fail a too-large upload BEFORE the network round-trip (the gateway caps the
/// multipart body — see [ChatUploadLimit]).
class PickedMedia {
  const PickedMedia({
    required this.path,
    required this.mimeType,
    required this.sizeBytes,
  });

  final String path;
  final String? mimeType;
  final int sizeBytes;
}

/// Picks one image/video for a chat attachment. A seam (like [DocumentPicker]) so the chat
/// composer + upload service are testable WITHOUT the platform `image_picker` channels.
abstract class ChatMediaPicker {
  /// The picked media, or `null` if the user cancelled.
  Future<PickedMedia?> pick(ChatAttachmentSource source);
}

/// Production [ChatMediaPicker] backed by the real `image_picker` plugin (already an app
/// dependency for guard documents — no new package).
class ImagePickerChatMediaPicker implements ChatMediaPicker {
  ImagePickerChatMediaPicker([ImagePicker? picker])
      : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<PickedMedia?> pick(ChatAttachmentSource source) async {
    final XFile? file = switch (source) {
      // Photos are lightly compressed (chat doesn't need full-res) and stay well under the
      // server's 10MB image cap.
      ChatAttachmentSource.cameraPhoto => await _picker.pickImage(
          source: ImageSource.camera, imageQuality: 80, maxWidth: 2000),
      ChatAttachmentSource.galleryPhoto => await _picker.pickImage(
          source: ImageSource.gallery, imageQuality: 80, maxWidth: 2000),
      ChatAttachmentSource.galleryVideo =>
        await _picker.pickVideo(source: ImageSource.gallery),
    };
    if (file == null) return null;
    return PickedMedia(
      path: file.path,
      mimeType: file.mimeType ?? ChatMime.fromPath(file.path),
      // `XFile.length()` reads the on-disk byte count (an int Future on all platforms).
      sizeBytes: await file.length(),
    );
  }
}

/// The client-side upload size ceiling for a chat attachment. This is NOT the chat service's own
/// per-kind cap (10MB image / 200MB video, `contracts/openapi/chat.yaml`); it is the **api-gateway
/// edge body cap** — `BodyCap::Large` = 12 MiB in
/// `services/api-gateway/src/domain/routing.rs` — which buffers the whole multipart body before
/// forwarding and 413s anything larger. Until that edge cap is raised for the video path, a video
/// over ~12 MiB cannot reach the chat service at all, so we reject it here with a clear, localized
/// message instead of firing a doomed POST that returns a bare 413 ("Request failed").
///
/// BACKEND FOLLOW-UP (flagged): raise the `POST /attachments` edge cap (a streaming/chunked
/// carve-out, or a higher `BodyCap` for this route) so the 200MB video contract is actually
/// reachable end-to-end; then relax this constant to match.
class ChatUploadLimit {
  const ChatUploadLimit._();

  /// 12 MiB — equals the api-gateway `BodyCap::LARGE_BYTES` for `POST /attachments`. We subtract a
  /// small multipart-framing margin so a file right at the limit still fits under the edge cap.
  static const int gatewayBodyCapBytes = 12 * 1024 * 1024;

  /// Multipart framing overhead headroom (boundaries + the `conversation_id` field + headers).
  static const int _framingMarginBytes = 64 * 1024;

  /// The largest picked-file size we will attempt to upload through the edge.
  static const int maxUploadBytes = gatewayBodyCapBytes - _framingMarginBytes;

  /// `true` if [sizeBytes] would be rejected by the edge body cap.
  static bool exceeds(int sizeBytes) => sizeBytes > maxUploadBytes;

  /// The cap rendered as whole MB for an error message.
  static int get maxMb => gatewayBodyCapBytes ~/ (1024 * 1024);
}

/// Pure MIME helpers for the attachment types the chat contract accepts
/// (JPEG/PNG/WEBP ≤10MB · MP4/MOV ≤200MB — `contracts/openapi/chat.yaml`).
class ChatMime {
  const ChatMime._();

  static const Map<String, String> _byExtension = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'webp': 'image/webp',
    'mp4': 'video/mp4',
    'mov': 'video/quicktime',
  };

  /// MIME type from a file path's extension; `null` when unknown.
  static String? fromPath(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) return null;
    return _byExtension[path.substring(dot + 1).toLowerCase()];
  }

  /// Whether [mimeType] is one the chat upload contract accepts.
  static bool isSupported(String? mimeType) =>
      mimeType != null && _byExtension.containsValue(mimeType);
}
