import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../../core/controllers/chat_attachment_resolver.dart';
import '../../../core/controllers/chat_format.dart';
import '../../../core/media/media_host.dart';
import '../../../core/models/chat.dart';

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
    // System messages render centred, not as a left/right bubble.
    if (message.type == ChatMessageType.system) {
      return Padding(
        padding: const EdgeInsets.symmetric(
            vertical: PgTokens.space2, horizontal: PgTokens.space4),
        child: Center(
          child: Text(
            message.content ?? '',
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
/// id; the presigned URL is resolved on view via [chatAttachmentProvider]
/// (`GET /v1/attachments/{id}` — TTL 1h, held in provider memory only, never persisted) and
/// rewritten by [MediaHost] so the device can reach the storage host. A `content` that is
/// already an absolute URL (forward-compat) renders directly. Video shows a labelled chip
/// (no in-app player dependency — documented gap).
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

    // Video renders as a labelled chip in every case (no in-app player — documented gap), so
    // never spend an authenticated GET resolving a presigned URL nothing would play.
    if (_isVideo) {
      return _chip(Icons.videocam_outlined, isThai ? 'วิดีโอ' : 'Video');
    }

    if (content.startsWith('http://') || content.startsWith('https://')) {
      return _BubbleImage(url: MediaHost.forApp(content), isThai: isThai, fg: fg);
    }

    final async = ref.watch(chatAttachmentProvider(content));
    return async.when(
      loading: () => _chip(Icons.image_outlined, isThai ? 'กำลังโหลด…' : 'Loading…'),
      error: (_, __) => _chip(
        Icons.broken_image_outlined,
        isThai ? 'โหลดไฟล์แนบไม่สำเร็จ' : 'Could not load attachment',
      ),
      data: (attachment) => _BubbleImage(
        url: MediaHost.forApp(attachment.fileUrl),
        isThai: isThai,
        fg: fg,
      ),
    );
  }

  Widget _fallbackChip() => _chip(
        _isVideo ? Icons.videocam_outlined : Icons.image_outlined,
        _isVideo ? (isThai ? 'วิดีโอ' : 'Video') : (isThai ? 'รูปภาพ' : 'Image'),
      );

  Widget _chip(IconData icon, String label) {
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
}

/// The inline image: constrained, rounded, with loading progress and a graceful error chip
/// (a presigned URL can expire mid-scroll — the error state invites a reopen, not a crash).
class _BubbleImage extends StatelessWidget {
  const _BubbleImage({required this.url, required this.isThai, required this.fg});

  final String url;
  final bool isThai;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
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
                    isThai ? 'รูปหมดอายุ — เปิดแชทใหม่' : 'Image expired — reopen chat',
                    style: TextStyle(fontSize: 13, color: fg),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
