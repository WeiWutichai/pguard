import 'package:image_picker/image_picker.dart';

/// Where a guard document image is sourced from.
enum DocSource { camera, gallery }

/// Picks a single document image for guard registration. A seam so the guard form is unit/widget
/// testable WITHOUT the platform `image_picker` plugin (tests override [documentPicker] with a fake
/// that returns a canned path); the production impl uses the REAL picker (camera or gallery).
abstract class DocumentPicker {
  /// The picked image's file path, or `null` if the user cancelled.
  Future<String?> pick(DocSource source);
}

/// Production [DocumentPicker] backed by the real `image_picker` plugin.
class ImagePickerDocumentPicker implements DocumentPicker {
  ImagePickerDocumentPicker([ImagePicker? picker])
      : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<String?> pick(DocSource source) async {
    final file = await _picker.pickImage(
      source:
          source == DocSource.camera ? ImageSource.camera : ImageSource.gallery,
      // Compress a little — document photos don't need full-res, and this keeps the eventual
      // upload small without losing legibility.
      imageQuality: 80,
      maxWidth: 2000,
    );
    return file?.path;
  }
}
