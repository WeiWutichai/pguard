import 'package:flutter/material.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../../core/controllers/relative_time.dart';
import '../../../core/models/chat.dart';

/// One row in the conversation list: counterpart avatar (initials fallback — no avatar endpoint
/// in v2), name, last message preview, last-message relative time, and an unread badge.
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

  static String _initials(String? name) {
    final n = (name ?? '').trim();
    if (n.isEmpty) return '?';
    final parts = n.split(RegExp(r'\s+'));
    if (parts.length >= 2 && parts[1].isNotEmpty) {
      return (parts[0][0] + parts[1][0]).toUpperCase();
    }
    return n.substring(0, n.length >= 2 ? 2 : 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final name = conversation.participantName ??
        (isThai ? 'การสนทนา' : 'Conversation');
    final preview = conversation.lastMessage ??
        (isThai ? 'แตะเพื่อเริ่มแชท' : 'Tap to start chatting');
    final when = conversation.lastMessageAt;
    final time = when == null
        ? ''
        : (isThai
            ? RelativeTime.th(when, now: DateTime.now().toUtc())
            : RelativeTime.en(when, now: DateTime.now().toUtc()));
    final unread = conversation.hasUnread;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: PgTokens.space4, vertical: PgTokens.space3),
        child: Row(
          children: [
            CircleAvatar(
              radius: 23,
              backgroundColor: PgTokens.colorGreen100,
              child: Text(
                _initials(conversation.participantName),
                style: const TextStyle(
                    color: PgTokens.colorGreen800,
                    fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: PgTokens.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
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
