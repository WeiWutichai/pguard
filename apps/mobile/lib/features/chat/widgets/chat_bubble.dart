import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../../core/controllers/chat_attachment_resolver.dart';
import '../../../core/controllers/chat_format.dart';
import '../../../core/media/media_host.dart';
import '../../../core/models/call.dart';
import '../../../core/models/chat.dart';
import '../../../core/network/api_exception.dart';
import 'chat_media_viewer.dart';

/// One message bubble. Side is decided by `sender_role == acting` ([ChatMessage.isFromRole]) —
/// right for the caller's own role, left for the counterpart — NEVER by sender id. Own bubbles
/// carry a delivered tick (the message is persisted once it echoes back); counterpart bubbles
/// carry a small 26px initials avatar (design row-them, [counterpartName]).
class ChatBubble extends StatelessWidget {
  const ChatBubble({
    super.key,
    required this.message,
    required this.acting,
    required this.isThai,
    this.counterpartName,
  });

  final ChatMessage message;
  final ChatRole acting;
  final bool isThai;

  /// Display name of the other participant — drives the initials avatar beside
  /// from-other bubbles (null → "?" initials).
  final String? counterpartName;

  static String _hm(DateTime utc) {
    final d = utc.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    // System messages render centred, not as a left/right bubble. A SERVER-emitted call summary
    // arrives as a `system` message whose content is the pinned call JSON — render it as the
    // localized WhatsApp-style line ("📞 สายเสียง · 2:34" / "📹 Video call · Missed call"); any
    // other system content renders verbatim.
    if (message.type == ChatMessageType.system) {
      final call = CallSummary.tryParseContent(message.content);
      final text = call == null
          ? (message.content ?? '')
          : CallSummary.line(
              type: call.type,
              outcome: call.outcome,
              thai: isThai,
              durationSeconds: call.durationSeconds,
            );
      return Padding(
        padding: const EdgeInsets.symmetric(
            vertical: PgTokens.space2, horizontal: PgTokens.space4),
        child: Center(
          child: Text(
            text,
            textAlign: TextAlign.center,
            style:
                const TextStyle(fontSize: 12, color: PgTokens.colorTextMuted),
          ),
        ),
      );
    }

    final mine = message.isFromRole(acting);
    // Design: own bubble is white-on-brand-int; them bubble is text-strong (= colorBrand
    // 0xFF0E3B2E, exactly the design's --text-strong light value) on white.
    final fg = mine ? Colors.white : PgTokens.colorBrand;

    final bubble = Container(
      constraints:
          BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.74),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: mine ? PgTokens.colorPrimary : PgTokens.colorSurface,
        // Design (them): borderless with a subtle xs shadow.
        boxShadow: mine
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(PgTokens.radius2xl),
          topRight: const Radius.circular(PgTokens.radius2xl),
          bottomLeft: Radius.circular(mine ? PgTokens.radius2xl : 5),
          bottomRight: Radius.circular(mine ? 5 : PgTokens.radius2xl),
        ),
      ),
      child: Column(
        crossAxisAlignment:
            mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _content(fg),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _hm(message.createdAt),
                style: TextStyle(
                  fontSize: 10,
                  // Design: timestamp row at 0.7 opacity of the bubble text color.
                  color: mine
                      ? Colors.white70
                      : PgTokens.colorBrand.withValues(alpha: 0.7),
                ),
              ),
              if (mine) ...[
                const SizedBox(width: 3),
                const Icon(Icons.done_all, size: 13, color: Colors.white70),
              ],
            ],
          ),
        ],
      ),
    );

    return Padding(
      padding:
          const EdgeInsets.symmetric(vertical: 3, horizontal: PgTokens.space4),
      child: Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: mine
            ? bubble
            // Design row-them: 26px initials avatar, 8px gap, bottom-aligned.
            : Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  CircleAvatar(
                    radius: 13,
                    backgroundColor: PgTokens.colorGreen100,
                    child: Text(
                      ChatFormat.initials(counterpartName),
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: PgTokens.colorGreen800,
                      ),
                    ),
                  ),
                  const SizedBox(width: PgTokens.space2),
                  Flexible(child: bubble),
                ],
              ),
      ),
    );
  }

  Widget _content(Color fg) {
    switch (message.type) {
      case ChatMessageType.image:
      case ChatMessageType.video:
        return _AttachmentContent(message: message, isThai: isThai, fg: fg);
      case ChatMessageType.text:
      case ChatMessageType.system:
        return Text(message.content ?? '',
            style: TextStyle(fontSize: 14, height: 1.45, color: fg));
    }
  }
}

/// Media content for an `image`/`video` message. The message `content` carries the attachment
/// id; the presigned URL is resolved via [chatAttachmentProvider] (`GET /v1/attachments/{id}` —
/// TTL 1h, held in provider memory only, never persisted) and rewritten by [MediaHost] so the
/// device can reach the storage host. A `content` that is already an absolute URL (forward-compat)
/// renders directly.
///
/// TAP TO VIEW (the fix): an IMAGE resolves its URL eagerly (it renders inline) and TAP opens the
/// full-screen zoomable viewer; a VIDEO renders a labelled chip WITHOUT an eager GET (nothing
/// inline to play) and resolves its URL ONLY on TAP, then opens the in-app player. So a video
/// still costs no GET until the user actually opens it.
class _AttachmentContent extends ConsumerWidget {
  const _AttachmentContent({
    required this.message,
    required this.isThai,
    required this.fg,
  });

  final ChatMessage message;
  final bool isThai;
  final Color fg;

  bool get _isVideo => message.type == ChatMessageType.video;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final content = message.content;
    if (content == null || content.isEmpty) return _fallbackChip();

    // Video: tappable chip, resolved lazily ON TAP (no eager GET — nothing renders inline).
    if (_isVideo) {
      return _VideoChip(
        attachmentRef: content,
        isThai: isThai,
        fg: fg,
      );
    }

    if (content.startsWith('http://') || content.startsWith('https://')) {
      return _BubbleImage(
          url: MediaHost.forApp(content), isThai: isThai, fg: fg);
    }

    final async = ref.watch(chatAttachmentProvider(content));
    return async.when(
      loading: () =>
          chip(Icons.image_outlined, isThai ? 'กำลังโหลด…' : 'Loading…', fg),
      error: (_, __) => chip(
        Icons.broken_image_outlined,
        isThai ? 'โหลดไฟล์แนบไม่สำเร็จ' : 'Could not load attachment',
        fg,
      ),
      data: (attachment) => _BubbleImage(
        url: MediaHost.forApp(attachment.fileUrl),
        isThai: isThai,
        fg: fg,
      ),
    );
  }

  Widget _fallbackChip() => chip(
        _isVideo ? Icons.videocam_outlined : Icons.image_outlined,
        _isVideo
            ? (isThai ? 'วิดีโอ' : 'Video')
            : (isThai ? 'รูปภาพ' : 'Image'),
        fg,
      );
}

/// A small icon+label chip used for video bubbles and image loading/error states.
Widget chip(IconData icon, String label, Color fg) {
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 18, color: fg),
      const SizedBox(width: 6),
      Flexible(
        child: Text(label,
            style: TextStyle(fontSize: 14, color: fg),
            overflow: TextOverflow.ellipsis),
      ),
    ],
  );
}

/// A tappable video bubble. Renders the "Video" chip with a play glyph; tapping RESOLVES the
/// attachment id to a fresh presigned URL ([chatAttachmentProvider]) and opens the in-app player
/// ([showChatVideoViewer]). The resolve happens only on tap (no eager GET); a resolve/permission
/// error surfaces as a snackbar rather than a dead tap. A `content` that is already an absolute
/// URL plays directly.
class _VideoChip extends ConsumerStatefulWidget {
  const _VideoChip({
    required this.attachmentRef,
    required this.isThai,
    required this.fg,
  });

  /// The attachment id (UUID) or an absolute URL carried in the message `content`.
  final String attachmentRef;
  final bool isThai;
  final Color fg;

  @override
  ConsumerState<_VideoChip> createState() => _VideoChipState();
}

class _VideoChipState extends ConsumerState<_VideoChip> {
  bool _busy = false;

  Future<void> _open() async {
    if (_busy) return;
    final ref0 = widget.attachmentRef;
    final messenger = ScaffoldMessenger.of(context);

    // Already an absolute URL → play directly (forward-compat path, no GET).
    if (ref0.startsWith('http://') || ref0.startsWith('https://')) {
      await showChatVideoViewer(context,
          url: MediaHost.forApp(ref0), isThai: widget.isThai);
      return;
    }

    setState(() => _busy = true);
    try {
      // Resolve a FRESH presigned URL only now (on tap); never persisted.
      final attachment = await ref.read(chatAttachmentProvider(ref0).future);
      // Re-check liveness after the await before touching `context` (the State's `mounted`
      // guards its `context`).
      if (!mounted) return;
      await showChatVideoViewer(context,
          url: MediaHost.forApp(attachment.fileUrl), isThai: widget.isThai);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(SnackBar(
        content: Text(
            widget.isThai ? 'เปิดวิดีโอไม่สำเร็จ' : 'Could not open video'),
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.isThai ? 'วิดีโอ' : 'Video';
    return InkWell(
      onTap: _busy ? null : _open,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_busy)
            SizedBox(
              width: 18,
              height: 18,
              child:
                  CircularProgressIndicator(strokeWidth: 2, color: widget.fg),
            )
          else
            Icon(Icons.play_circle_outline, size: 20, color: widget.fg),
          const SizedBox(width: 6),
          Flexible(
            child: Text(label,
                style: TextStyle(fontSize: 14, color: widget.fg),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

/// The inline image: constrained, rounded, with loading progress and a graceful error chip
/// (a presigned URL can expire mid-scroll — the error state invites a reopen, not a crash).
/// TAP opens the full-screen zoomable viewer ([showChatImageViewer]) on the SAME presigned URL.
class _BubbleImage extends StatelessWidget {
  const _BubbleImage(
      {required this.url, required this.isThai, required this.fg});

  final String url;
  final bool isThai;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => showChatImageViewer(context, url: url, isThai: isThai),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(PgTokens.radiusMd),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 220, maxHeight: 240),
          child: Image.network(
            url,
            fit: BoxFit.cover,
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return const SizedBox(
                width: 220,
                height: 140,
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            },
            errorBuilder: (context, _, __) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.broken_image_outlined, size: 18, color: fg),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      isThai
                          ? 'รูปหมดอายุ — เปิดแชทใหม่'
                          : 'Image expired — reopen chat',
                      style: TextStyle(fontSize: 13, color: fg),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
