import 'dart:io';

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pguard_mobile/core/media/photo_capture.dart';

void main() {
  late Directory tmp;
  late File jpg;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('pguard_capture_test');
    jpg = File('${tmp.path}/shot.jpg')..writeAsBytesSync(List<int>.filled(123, 7));
  });

  tearDown(() => tmp.delete(recursive: true));

  test('a picked file becomes a CapturedPhoto with its path + real size', () async {
    final service =
        ImagePickerPhotoCaptureService(pick: () async => XFile(jpg.path));
    final photo = await service.capture();
    expect(photo, isNotNull);
    expect(photo!.path, jpg.path);
    expect(photo.sizeBytes, 123, reason: 'size read from the file on disk');
  });

  test('a cancelled pick (null) → null (the sheet shows the camera as unavailable)',
      () async {
    final service = ImagePickerPhotoCaptureService(pick: () async => null);
    expect(await service.capture(), isNull);
  });

  test('a permission-denied PlatformException → null (never crashes the flow)',
      () async {
    final service = ImagePickerPhotoCaptureService(
      pick: () async =>
          throw PlatformException(code: 'camera_access_denied'),
    );
    expect(await service.capture(), isNull);
  });

  test('the unavailable fallback always returns null', () async {
    expect(await const UnavailablePhotoCaptureService().capture(), isNull);
  });
}
