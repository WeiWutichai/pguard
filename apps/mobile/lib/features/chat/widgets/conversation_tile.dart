import 'package:flutter/material.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../../core/controllers/chat_format.dart';
import '../../../core/models/chat.dart';

/// One row in the conversation list: counterpart avatar (initials fallback — no avatar endpoint
/// in v2), name, last message preview, last-message time bucket (design: absolute — clock time
/// today, "เมื่อวาน" yesterday, short date older), and an unread badge.
class ConversationTile extends StatelessWidget {
  const ConversationTile({
    super.key,
    required this.conversation,
    required this.isThai,
    required this.onTap,
  });

  final Conversation conversation;
  final bool isThai;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = conversation.participantName ??
        (isThai ? 'การสนทนา' : 'Conversation');
    // Localize the last-message preview: a SERVER-emitted call-summary `system` message has its
    // content as the pinned call JSON — render the one-line summary, not the raw '{"k":"call",…}'
    // (reuses CallSummary via ChatFormat). Other messages render verbatim; null → placeholder.
    final preview = ChatFormat.lastMessagePreview(conversation.lastMessage,
            thai: isThai) ??
        (isThai ? 'แตะเพื่อเริ่มแชท' : 'Tap to start chatting');
    final when = conversation.lastMessageAt;
    final time = when == null
        ? ''
        : ChatFormat.listTime(when, now: DateTime.now(), thai: isThai);
    final unread = conversation.hasUnread;

    return InkWell(
      onTap: onTap,
      child: Padding(
        // Design: row padding 14px 20px, gap 13px (non-token design metrics).
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24, // design: 48px list avatar
              backgroundColor: PgTokens.colorGreen100,
              child: Text(
                ChatFormat.initials(conversation.participantName),
                style: const TextStyle(
                    color: PgTokens.colorGreen800,
                    fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: unread ? FontWeight.w700 : FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          unread ? FontWeight.w500 : FontWeight.w400,
                      color: unread
                          ? PgTokens.colorText
                          : PgTokens.colorTextMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: PgTokens.space2),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(time,
                    style: const TextStyle(
                        fontSize: 11, color: PgTokens.colorTextFaint)),
                const SizedBox(height: 6),
                if (unread)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: PgTokens.colorPrimary,
                      borderRadius: BorderRadius.circular(PgTokens.radiusFull),
                    ),
                    constraints: const BoxConstraints(minWidth: 20),
                    child: Text(
                      conversation.unreadCount > 99
                          ? '99+'
                          : '${conversation.unreadCount}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700),
                    ),
                  )
                else
                  const SizedBox(height: 20),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
