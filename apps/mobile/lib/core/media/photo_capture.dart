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
///
/// NATIVE DEPENDENCY (documented): real capture needs the `image_picker` plugin
/// (`ImageSource.camera`) wired into this provider; until then [capture] returns null and the
/// UI shows the camera as unavailable.
abstract class PhotoCaptureService {
  /// Capture (or pick) a photo; `null` if cancelled or no camera is available.
  Future<CapturedPhoto?> capture();
}

/// Offline-safe default: no camera plugin → always null.
class UnavailablePhotoCaptureService implements PhotoCaptureService {
  const UnavailablePhotoCaptureService();

  @override
  Future<CapturedPhoto?> capture() async => null;
}
