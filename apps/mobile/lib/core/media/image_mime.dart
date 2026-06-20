import 'dart:io';

/// Detect an image MIME from the file's MAGIC BYTES — mirrors the server's `detect_image_mime`
/// (services/profile/src/domain/documents.rs). The file EXTENSION is unreliable: `image_picker`
/// re-encodes a capture to JPEG while keeping the source filename, so the declared Content-Type
/// MUST come from the actual content or the server's magic-byte check rejects the upload. Returns
/// null for anything that isn't JPEG/PNG/WEBP (caller treats it as "not a supported image").
String? detectImageMime(List<int> head) {
  if (head.length >= 3 && head[0] == 0xFF && head[1] == 0xD8 && head[2] == 0xFF) {
    return 'image/jpeg';
  }
  if (head.length >= 8 &&
      head[0] == 0x89 &&
      head[1] == 0x50 &&
      head[2] == 0x4E &&
      head[3] == 0x47 &&
      head[4] == 0x0D &&
      head[5] == 0x0A &&
      head[6] == 0x1A &&
      head[7] == 0x0A) {
    return 'image/png';
  }
  if (head.length >= 12 &&
      head[0] == 0x52 &&
      head[1] == 0x49 &&
      head[2] == 0x46 &&
      head[3] == 0x46 &&
      head[8] == 0x57 &&
      head[9] == 0x45 &&
      head[10] == 0x42 &&
      head[11] == 0x50) {
    return 'image/webp';
  }
  return null;
}

/// Read the first [n] bytes of [path] (enough for a magic-byte sniff) without loading the whole
/// file into memory.
Future<List<int>> readImageHead(String path, int n) async {
  final f = await File(path).open();
  try {
    return await f.read(n);
  } finally {
    await f.close();
  }
}
