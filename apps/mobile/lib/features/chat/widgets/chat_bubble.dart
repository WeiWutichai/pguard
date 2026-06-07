import 'package:flutter/material.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../../core/models/chat.dart';

/// One message bubble. Side is decided by `sender_role == acting` ([ChatMessage.isFromRole]) —
/// right for the caller's own role, left for the counterpart — NEVER by sender id. Own bubbles
/// carry a delivered tick (the message is persisted once it echoes back).
class ChatBubble extends StatelessWidget {
  const ChatBubble({
    super.key,
    required this.message,
    required this.acting,
    required this.isThai,
  });

  final ChatMessage message;
  final ChatRole acting;
  final bool isThai;

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
    final fg = mine ? Colors.white : PgTokens.colorText;

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.76),
        margin: const EdgeInsets.symmetric(
            vertical: 3, horizontal: PgTokens.space4),
        padding: const EdgeInsets.symmetric(
            horizontal: PgTokens.space3, vertical: PgTokens.space2),
        decoration: BoxDecoration(
          color: mine ? PgTokens.colorPrimary : PgTokens.colorSurface,
          border: mine ? null : Border.all(color: PgTokens.colorBorder),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(PgTokens.radiusLg),
            topRight: const Radius.circular(PgTokens.radiusLg),
            bottomLeft: Radius.circular(mine ? PgTokens.radiusLg : 2),
            bottomRight: Radius.circular(mine ? 2 : PgTokens.radiusLg),
          ),
        ),
        child: Column(
          crossAxisAlignment:
              mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _content(fg),
            const SizedBox(height: 3),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _hm(message.createdAt),
                  style: TextStyle(
                    fontSize: 10.5,
                    color: mine ? Colors.white70 : PgTokens.colorTextFaint,
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
      ),
    );
  }

  Widget _content(Color fg) {
    switch (message.type) {
      case ChatMessageType.image:
        return _MediaChip(
          icon: Icons.image_outlined,
          label: isThai ? 'รูปภาพ' : 'Image',
          fg: fg,
        );
      case ChatMessageType.video:
        return _MediaChip(
          icon: Icons.videocam_outlined,
          label: isThai ? 'วิดีโอ' : 'Video',
          fg: fg,
        );
      case ChatMessageType.text:
      case ChatMessageType.system:
        return Text(message.content ?? '',
            style: TextStyle(fontSize: 14.5, color: fg));
    }
  }
}

/// An attachment placeholder. The presigned URL is resolved on demand via
/// `GET /v1/attachments/{id}` (the message `content` carries the attachment id) and rewritten by
/// [MediaHost] before display — wired once an image/video picker plugin lands (see
/// `ChatAttachmentService`). Until then the bubble shows a labelled media chip.
class _MediaChip extends StatelessWidget {
  const _MediaChip({required this.icon, required this.label, required this.fg});

  final IconData icon;
  final String label;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: fg),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 14, color: fg)),
      ],
    );
  }
}
