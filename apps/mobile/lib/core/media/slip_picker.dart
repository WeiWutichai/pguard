import 'package:image_picker/image_picker.dart';

/// Where the customer's transfer-SLIP image is sourced from.
enum SlipSource { camera, gallery }

/// Picks a single PromptPay transfer-slip image (the customer either screenshots their banking app
/// — gallery — or photographs a printed receipt — camera). A seam so the pay flow is unit/widget
/// testable WITHOUT the platform `image_picker` plugin (tests override [slipPicker] with a fake that
/// returns a canned path); production uses the REAL picker.
abstract class SlipPicker {
  /// The picked image's file path, or `null` if the user cancelled.
  Future<String?> pick(SlipSource source);
}

/// Production [SlipPicker] backed by the real `image_picker` plugin (already an app dependency).
/// The slip is lightly compressed (same knobs as the document/avatar pickers) so the JPEG stays
/// under the server's image cap and the gateway's body cap — slips are legible at this quality.
class ImagePickerSlipPicker implements SlipPicker {
  ImagePickerSlipPicker([ImagePicker? picker]) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<String?> pick(SlipSource source) async {
    final file = await _picker.pickImage(
      source: source == SlipSource.camera
          ? ImageSource.camera
          : ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 2000,
    );
    return file?.path;
  }
}
