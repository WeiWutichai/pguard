import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../core/controllers/chat_list_controller.dart';
import '../../core/controllers/locale_controller.dart';
import '../../core/models/chat.dart';
import '../../core/network/api_exception.dart';
import '../../widgets/pg_error_state.dart';
import '../../widgets/pguard_header.dart';
import 'chat_routes.dart';
import 'widgets/conversation_tile.dart';

/// The conversation list for the caller's acting role (guard dashboard → guard; customer →
/// customer). One enriched REST call (N+1-free); pull-to-refresh; NO polling. Tapping a row opens
/// the real-time conversation, passing the acting role + the read-only flag (from request status).
class ChatListScreen extends ConsumerWidget {
  const ChatListScreen({super.key, required this.actingRole});

  final ChatRole actingRole;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(chatListControllerProvider(actingRole));
    final ctrl = ref.read(chatListControllerProvider(actingRole).notifier);
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;

    return Scaffold(
      backgroundColor: PgTokens.colorBg,
      appBar: const PGuardHeader(
        title: 'ข้อความ',
        subtitle: 'Messages',
        showBack: true,
      ),
      body: SafeArea(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => PgErrorState(
            title: 'โหลดแชทไม่สำเร็จ / Could not load chats',
            message: e is ApiException ? e.message : null,
            onRetry: ctrl.refresh,
          ),
          data: (list) => RefreshIndicator(
            onRefresh: ctrl.refresh,
            child: list.isEmpty
                ? const _EmptyBody()
                : ListView.separated(
                    itemCount: list.length,
                    // Design: full-bleed 1px border under each row (no avatar indent).
                    separatorBuilder: (_, __) => const Divider(
                        height: 1, color: PgTokens.colorBorder),
                    itemBuilder: (_, i) {
                      final c = list[i];
                      return ConversationTile(
                        conversation: c,
                        isThai: isThai,
                        onTap: () => context.push(
                          ChatRoutes.conversation(
                            c.id,
                            acting: actingRole,
                            readOnly: c.isReadOnly,
                          ),
                          extra: c.participantName,
                        ),
                      );
                    },
                  ),
          ),
        ),
      ),
    );
  }
}

class _EmptyBody extends StatelessWidget {
  const _EmptyBody();

  @override
  Widget build(BuildContext context) {
    return ListView(
      // ListView so pull-to-refresh still works on the empty state.
      children: const [
        SizedBox(height: 120),
        Icon(Icons.forum_outlined, size: 48, color: PgTokens.colorTextFaint),
        SizedBox(height: PgTokens.space3),
        Center(
          child: Text(
            'ยังไม่มีการสนทนา\nNo conversations yet',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: PgTokens.colorText),
          ),
        ),
        SizedBox(height: PgTokens.space2),
        Center(
          child: Text(
            'แชทกับคู่สนทนาเมื่อมีงานที่กำลังดำเนินอยู่\nChat opens when you have an active job',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: PgTokens.colorTextMuted),
          ),
        ),
      ],
    );
  }
}
