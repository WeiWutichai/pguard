import 'package:image_picker/image_picker.dart';

/// Where a chat attachment comes from (the composer's source sheet).
enum ChatAttachmentSource { cameraPhoto, galleryPhoto, galleryVideo }

/// A picked media file, ready to upload. [mimeType] may be null when neither the platform nor
/// the file extension could identify it (the upload service rejects it with a friendly error
/// rather than letting the server's magic-byte check fail later).
class PickedMedia {
  const PickedMedia({required this.path, required this.mimeType});

  final String path;
  final String? mimeType;
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
    );
  }
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
