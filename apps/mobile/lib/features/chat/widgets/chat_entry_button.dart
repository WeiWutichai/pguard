import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../../core/controllers/chat_launcher.dart';
import '../../../core/controllers/chat_list_controller.dart';
import '../../../core/controllers/locale_controller.dart';
import '../../../core/models/chat.dart';
import '../../../core/network/api_exception.dart';
import '../chat_routes.dart';
import 'chat_unread_badge.dart';

/// A chat-open button for an entry-point screen (guard active job / customer live status). On tap
/// it resolves the booking's conversation (find-or-create — `POST /conversations` is not
/// idempotent, so [ChatLauncher] finds first) and navigates to it, threading the acting role +
/// the read-only flag (from the booking status). Disabled until both user ids are known.
///
/// [counterpartName] may be null: the v2 `Booking` model carries no counterpart display name, so a
/// created conversation stores a null name and the list tile falls back to a generic label until
/// the booking event path supplies one. Chat + unread counts are unaffected (display-only gap).
class ChatEntryButton extends ConsumerStatefulWidget {
  const ChatEntryButton({
    super.key,
    required this.requestId,
    required this.requestStatus,
    required this.acting,
    required this.myUserId,
    required this.counterpartUserId,
    this.counterpartName,
  });

  final String requestId;

  /// Booking lifecycle status wire value (drives the read-only flag passed to the chat screen).
  final String? requestStatus;
  final ChatRole acting;
  final String? myUserId;
  final String? counterpartUserId;
  final String? counterpartName;

  @override
  ConsumerState<ChatEntryButton> createState() => _ChatEntryButtonState();
}

class _ChatEntryButtonState extends ConsumerState<ChatEntryButton> {
  bool _busy = false;

  bool get _enabled =>
      widget.myUserId != null && widget.counterpartUserId != null && !_busy;

  Future<void> _open() async {
    final myId = widget.myUserId;
    final otherId = widget.counterpartUserId;
    if (myId == null || otherId == null || _busy) return;

    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final isThai = ref.read(localeControllerProvider) == AppLocale.th;
    final launcher = ref.read(chatLauncherProvider);
    final counterRole =
        widget.acting == ChatRole.guard ? ChatRole.customer : ChatRole.guard;

    setState(() => _busy = true);
    try {
      final conversationId = await launcher.resolveConversationId(
        requestId: widget.requestId,
        acting: widget.acting,
        requestStatus: widget.requestStatus,
        participants: [
          ParticipantInput(userId: myId, role: widget.acting),
          ParticipantInput(
              userId: otherId,
              role: counterRole,
              displayName: widget.counterpartName),
        ],
      );
      if (!mounted) return;
      await router.push(
        ChatRoutes.conversation(
          conversationId,
          acting: widget.acting,
          readOnly: ChatReadOnly.fromStatus(widget.requestStatus),
        ),
        extra: widget.counterpartName,
      );
      // Opening the conversation marked it read server-side; re-pull the list so the
      // unread badge catches up (gesture-driven, not a poll).
      if (mounted) ref.invalidate(chatListControllerProvider(widget.acting));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(SnackBar(
          content: Text(isThai ? 'เปิดแชทไม่สำเร็จ' : 'Could not open chat')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChatUnreadBadge(
      acting: widget.acting,
      requestId: widget.requestId,
      child: Material(
        color: PgTokens.colorSunken,
        borderRadius: BorderRadius.circular(PgTokens.radiusLg),
        child: InkWell(
          onTap: _enabled ? _open : null,
          borderRadius: BorderRadius.circular(PgTokens.radiusLg),
          child: SizedBox(
            width: 44,
            height: 44,
            child: _busy
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    Icons.chat_bubble_outline,
                    size: 20,
                    color: _enabled
                        ? PgTokens.colorPrimary
                        : PgTokens.colorTextFaint,
                  ),
          ),
        ),
      ),
    );
  }
}
