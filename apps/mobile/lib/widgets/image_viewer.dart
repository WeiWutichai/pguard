import 'package:flutter/material.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

/// Open a full-screen, pinch-to-zoom viewer for [url] over a dark scrim.
///
/// The shared "tap a picture to see it big" affordance — used by the profile avatar (own) and the
/// guard card avatar (the other party). Mirrors the chat attachment viewer
/// (`features/chat/widgets/chat_media_viewer.dart`), which keeps its own copy because its copy is
/// attachment-specific (a presigned URL that can expire mid-view gets a "reopen" hint). A failed
/// load here degrades to an honest message instead of a broken glyph.
Future<void> showImageViewer(
  BuildContext context, {
  required String url,
  required bool isThai,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.92),
    builder: (_) => _ImageViewer(url: url, isThai: isThai),
  );
}

class _ImageViewer extends StatelessWidget {
  const _ImageViewer({required this.url, required this.isThai});

  final String url;
  final bool isThai;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(PgTokens.space3),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              tooltip: isThai ? 'ปิด' : 'Close',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          Flexible(
            child: InteractiveViewer(
              maxScale: 4,
              child: Image.network(
                url,
                fit: BoxFit.contain,
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return const SizedBox(
                    height: 240,
                    child: Center(
                      child: SizedBox(
                        width: 26,
                        height: 26,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      ),
                    ),
                  );
                },
                errorBuilder: (context, _, __) => SizedBox(
                  height: 240,
                  child: Center(
                    child: Text(
                      isThai ? 'โหลดรูปไม่สำเร็จ' : 'Could not load the image',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
