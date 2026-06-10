import 'package:flutter/services.dart' show PlatformException;
import 'package:image_picker/image_picker.dart';

/// A captured check-in photo. Carries a local file path + size only — the bytes stay on disk
/// until upload (no decoding in Dart). Pure value type.
class CapturedPhoto {
  const CapturedPhoto({required this.path, required this.sizeBytes});

  final String path;
  final int sizeBytes;
}

/// Captures a checkpoint photo for the hourly check-in.
///
/// Abstracted so the check-in flow is testable without the camera/native channels.
abstract class PhotoCaptureService {
  /// Capture a photo; `null` if cancelled or no camera is available/permitted.
  Future<CapturedPhoto?> capture();
}

/// Production capture via the real `image_picker` plugin (`ImageSource.camera`) — already an
/// app dependency (registration + chat media picker), so no new package. The photo is lightly
/// compressed (same knobs as the chat picker) so the JPEG stays well under the server's 10MB
/// image cap and the gateway's 12MB body cap.
///
/// The actual pick is injectable (`pick`) so the capture→CapturedPhoto mapping is unit-testable
/// without the platform channels; production uses the real camera.
class ImagePickerPhotoCaptureService implements PhotoCaptureService {
  ImagePickerPhotoCaptureService({Future<XFile?> Function()? pick})
      : _pick = pick ?? _cameraPick;

  final Future<XFile?> Function() _pick;

  static Future<XFile?> _cameraPick() => ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: 80,
        maxWidth: 2000,
      );

  @override
  Future<CapturedPhoto?> capture() async {
    try {
      final file = await _pick();
      if (file == null) return null; // user cancelled
      return CapturedPhoto(path: file.path, sizeBytes: await file.length());
    } on PlatformException {
      // No camera / permission denied → treat like a cancel; the sheet shows the camera as
      // unavailable (a null capture). Never crashes the check-in flow.
      return null;
    }
  }
}

/// Offline-safe fallback: no camera → always null. Tests override the provider with a fake.
class UnavailablePhotoCaptureService implements PhotoCaptureService {
  const UnavailablePhotoCaptureService();

  @override
  Future<CapturedPhoto?> capture() async => null;
}
