// The OS handoff for a generated document: bytes → a real file on disk → the system share sheet,
// from which the customer can save it to Files/Downloads, send it over LINE, mail it or print it.
//
// This is a THIN seam on purpose. It contains no document logic at all, so the PDF builder
// (`receipt_pdf.dart`) stays the only thing that decides what the paper says, and tests can drive
// the download end-to-end — really building the PDF — while overriding just this last step instead
// of stubbing out platform channels (`path_provider` + `share_plus`).
//
// House pattern: same "write into a temp dir then `Share.shareXFiles`" route the PromptPay QR
// already uses (`features/booking/widgets/promptpay_slip_panel.dart`).

import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Hands a finished document to the operating system.
abstract class DocumentSharer {
  /// Persist [bytes] under [fileName] and open the OS share sheet on it.
  ///
  /// [fileName] is the name the customer will see wherever the file lands, so callers pass a
  /// meaningful one (the document number) — never a temp name.
  Future<void> shareBytes({
    required Uint8List bytes,
    required String fileName,
    String mimeType = 'application/pdf',
    String? subject,
  });
}

/// The real implementation: a file in the app's temporary directory (the OS reclaims it; the
/// customer's own copy is whatever the share target saved), then `Share.shareXFiles`.
class TempFileDocumentSharer implements DocumentSharer {
  const TempFileDocumentSharer();

  @override
  Future<void> shareBytes({
    required Uint8List bytes,
    required String fileName,
    String mimeType = 'application/pdf',
    String? subject,
  }) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: mimeType, name: fileName)],
      subject: subject,
    );
  }
}
