import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../../core/controllers/chat_list_controller.dart';
import '../../../core/models/chat.dart';

/// Overlays a chat entry point with its unread count, fed by the existing
/// [ChatListController] (one `GET /conversations?role=` per controller lifetime — pull-based,
/// no polling; entry points invalidate the controller after a conversation closes so the badge
/// catches up). [requestId] narrows the count to one booking's conversation; `null` = total.
/// Renders only [child] while the list is loading/failed or the count is zero.
class ChatUnreadBadge extends ConsumerWidget {
  const ChatUnreadBadge({
    super.key,
    required this.acting,
    required this.child,
    this.requestId,
  });

  final ChatRole acting;
  final String? requestId;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversations =
        ref.watch(chatListControllerProvider(acting)).valueOrNull;
    final count = conversations == null
        ? 0
        : unreadTotal(conversations, requestId: requestId);
    if (count == 0) return child;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          right: -4,
          top: -4,
          child: IgnorePointer(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              constraints: const BoxConstraints(minWidth: 17),
              decoration: BoxDecoration(
                color: PgTokens.colorDanger,
                borderRadius: BorderRadius.circular(PgTokens.radiusFull),
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: Text(
                count > 99 ? '99+' : '$count',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  height: 1,
                  // Match the notification bell: IBMPlexSansThai's oversized ascent floats the
                  // digit up under the default proportional leading — `even` recentres it.
                  leadingDistribution: TextLeadingDistribution.even,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
