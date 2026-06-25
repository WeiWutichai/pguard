import 'package:flutter/material.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';
import 'package:video_player/video_player.dart';

/// Full-screen viewers for a chat attachment. An IMAGE opens a pinch-to-zoom viewer
/// ([showChatImageViewer], mirrors `progress_report_viewer`); a VIDEO opens an in-app player
/// ([showChatVideoViewer], `video_player`). Both take a FRESH presigned URL (TTL ~1h, re-signed
/// per `GET /attachments/{id}`) — a long-open viewer can outlive it, so each degrades to a
/// "reopen" hint on a load/init error instead of a broken glyph or a stuck spinner.
///
/// The URL is already [MediaHost]-rewritten by the caller (so the device can reach the storage
/// host); these widgets never rewrite it again.

/// Open the full-screen zoomable image viewer over a dark scrim.
Future<void> showChatImageViewer(
  BuildContext context, {
  required String url,
  required bool isThai,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.92),
    builder: (_) => _ChatImageViewer(url: url, isThai: isThai),
  );
}

/// Open the full-screen in-app video player over a dark scrim.
Future<void> showChatVideoViewer(
  BuildContext context, {
  required String url,
  required bool isThai,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.95),
    builder: (_) => _ChatVideoViewer(url: url, isThai: isThai),
  );
}

/// A right-aligned white close affordance over the dark scrim — shared chrome for both viewers.
class _CloseRow extends StatelessWidget {
  const _CloseRow({required this.isThai});

  final bool isThai;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: IconButton(
        icon: const Icon(Icons.close, color: Colors.white),
        tooltip: isThai ? 'ปิด' : 'Close',
        onPressed: () => Navigator.of(context).pop(),
      ),
    );
  }
}

class _ChatImageViewer extends StatelessWidget {
  const _ChatImageViewer({required this.url, required this.isThai});

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
          _CloseRow(isThai: isThai),
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
                errorBuilder: (context, _, __) => _expired(isThai),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// In-app video player: initializes a [VideoPlayerController] on the presigned URL, shows a
/// spinner while it loads, auto-plays once ready, and offers a tap-to-toggle play/pause over the
/// frame. A failed init (expired URL / unsupported codec) degrades to the same "reopen" hint.
class _ChatVideoViewer extends StatefulWidget {
  const _ChatVideoViewer({required this.url, required this.isThai});

  final String url;
  final bool isThai;

  @override
  State<_ChatVideoViewer> createState() => _ChatVideoViewerState();
}

class _ChatVideoViewerState extends State<_ChatVideoViewer> {
  VideoPlayerController? _controller;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _controller = controller;
    try {
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      await controller.setLooping(false);
      await controller.play();
      setState(() {});
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _togglePlay() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    setState(() => c.value.isPlaying ? c.pause() : c.play());
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    final ready = !_failed && c != null && c.value.isInitialized;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(PgTokens.space3),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CloseRow(isThai: widget.isThai),
          Flexible(
            child: _failed
                ? _expired(widget.isThai, video: true)
                : !ready
                    ? const SizedBox(
                        height: 240,
                        child: Center(
                          child: SizedBox(
                            width: 26,
                            height: 26,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          ),
                        ),
                      )
                    : GestureDetector(
                        onTap: _togglePlay,
                        child: AspectRatio(
                          aspectRatio: c.value.aspectRatio == 0
                              ? 16 / 9
                              : c.value.aspectRatio,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              VideoPlayer(c),
                              if (!c.value.isPlaying)
                                const Icon(Icons.play_circle_fill,
                                    size: 64, color: Colors.white70),
                              Positioned(
                                left: 0,
                                right: 0,
                                bottom: 0,
                                child: VideoProgressIndicator(
                                  c,
                                  allowScrubbing: true,
                                  colors: const VideoProgressColors(
                                    playedColor: PgTokens.colorPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

/// A presigned URL can expire while the viewer is open — degrade to a "reopen" hint, not a crash.
Widget _expired(bool isThai, {bool video = false}) => Padding(
      padding: const EdgeInsets.symmetric(
          vertical: PgTokens.space8, horizontal: PgTokens.space4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            video ? Icons.videocam_off_outlined : Icons.broken_image_outlined,
            size: 30,
            color: Colors.white70,
          ),
          const SizedBox(height: PgTokens.space2),
          Text(
            video
                ? (isThai
                    ? 'เล่นวิดีโอไม่ได้ — เปิดแชทใหม่'
                    : 'Could not play video — reopen chat')
                : (isThai
                    ? 'รูปหมดอายุ — เปิดแชทใหม่'
                    : 'Image expired — reopen chat'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: Colors.white70),
          ),
        ],
      ),
    );
