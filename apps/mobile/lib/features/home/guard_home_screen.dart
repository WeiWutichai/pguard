import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../core/controllers/guard_jobs_controller.dart';
import '../../core/models/booking.dart';
import '../../core/models/chat.dart';
import '../../core/network/api_exception.dart';
import '../../widgets/pguard_header.dart';
import '../../widgets/primary_button.dart';
import '../chat/chat_routes.dart';
import '../chat/widgets/chat_unread_badge.dart';
import '../guard/widgets/job_card.dart';
import '../guard/widgets/online_card.dart';
import '../notifications/widgets/notification_bell.dart';

/// Guard dashboard (role landing): online/standby GPS toggle + the guard's jobs (incoming to
/// accept, active to work). UI per `Mobile - Guard App.html` / `Mobile - Active Standby.html`.
class GuardHomeScreen extends ConsumerWidget {
  const GuardHomeScreen({super.key});

  Future<void> _accept(BuildContext context, WidgetRef ref, String id) async {
    final err = await ref.read(guardJobsControllerProvider.notifier).accept(id);
    if (!context.mounted) return;
    if (err != null) {
      _snack(context, err);
    } else {
      context.push('/guard/active/$id');
    }
  }

  // First-come-accept: an unaccepted offer can't be "declined" server-side — just hide it.
  void _dismiss(WidgetRef ref, String id) =>
      ref.read(guardJobsControllerProvider.notifier).dismiss(id);

  static void _snack(BuildContext context, String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobs = ref.watch(guardJobsControllerProvider);

    return Scaffold(
      backgroundColor: PgTokens.colorBg,
      appBar: PGuardHeader(
        title: 'pguard',
        subtitle: 'เจ้าหน้าที่ · Guard',
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const NotificationBell(),
            ChatUnreadBadge(
              acting: ChatRole.guard,
              child: IconButton(
                icon: const Icon(Icons.forum_outlined,
                    color: Colors.white, size: 22),
                tooltip: 'แชท / Chat',
                onPressed: () => context.push(ChatRoutes.list(ChatRole.guard)),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.person_outline,
                  color: Colors.white, size: 22),
              tooltip: 'โปรไฟล์ / Profile',
              onPressed: () => context.push('/profile'),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () =>
              ref.read(guardJobsControllerProvider.notifier).refresh(),
          child: ListView(
            padding: const EdgeInsets.all(PgTokens.space4),
            children: [
              const OnlineCard(),
              const SizedBox(height: PgTokens.space4),
              jobs.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(PgTokens.space6),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => _JobsError(
                  message: e is ApiException
                      ? e.message
                      : 'โหลดงานไม่สำเร็จ / Could not load jobs',
                ),
                data: (all) => _JobsBody(
                  incoming: GuardJobsController.incoming(all),
                  active: GuardJobsController.active(all),
                  onAccept: (id) => _accept(context, ref, id),
                  onDismiss: (id) => _dismiss(ref, id),
                  onOpenActive: (id) => context.push('/guard/active/$id'),
                  onOpenDetail: (id) => context.push('/guard/job/$id'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _JobsBody extends StatelessWidget {
  const _JobsBody({
    required this.incoming,
    required this.active,
    required this.onAccept,
    required this.onDismiss,
    required this.onOpenActive,
    required this.onOpenDetail,
  });

  final List<Booking> incoming;
  final List<Booking> active;
  final void Function(String id) onAccept;
  final void Function(String id) onDismiss;
  final void Function(String id) onOpenActive;
  final void Function(String id) onOpenDetail;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (active.isNotEmpty) ...[
          const _SectionHeader('งานที่กำลังทำ / Active'),
          for (final b in active) ...[
            GuardJobCard(booking: b, onTap: () => onOpenActive(b.id)),
            const SizedBox(height: PgTokens.space3),
          ],
        ],
        const _SectionHeader('งานรอตอบรับ / Incoming'),
        if (incoming.isEmpty)
          const _EmptyIncoming()
        else
          for (final b in incoming) ...[
            GuardJobCard(
              booking: b,
              highlight: true,
              onTap: () => onOpenDetail(b.id),
              actions: Row(
                children: [
                  SizedBox(
                    width: 96,
                    child: PgGhostButton(
                      label: 'ข้าม',
                      onPressed: () => onDismiss(b.id),
                    ),
                  ),
                  const SizedBox(width: PgTokens.space2),
                  Expanded(
                    child: PgPrimaryButton(
                      label: 'รับงาน / Accept',
                      onPressed: () => onAccept(b.id),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: PgTokens.space3),
          ],
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: PgTokens.space2),
        child: Text(text,
            style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w600)),
      );
}

class _EmptyIncoming extends StatelessWidget {
  const _EmptyIncoming();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(PgTokens.space4),
      decoration: BoxDecoration(
        color: PgTokens.colorSurface,
        borderRadius: BorderRadius.circular(PgTokens.radiusLg),
        border: Border.all(color: PgTokens.colorBorder),
      ),
      child: const Text(
        'ยังไม่มีงานใหม่ — เปิดสถานะออนไลน์เพื่อรับงาน\nNo new jobs — go online to receive offers',
        style: TextStyle(color: PgTokens.colorTextMuted, fontSize: 13),
      ),
    );
  }
}

class _JobsError extends StatelessWidget {
  const _JobsError({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(PgTokens.space4),
      decoration: BoxDecoration(
        color: PgTokens.colorDangerBg,
        borderRadius: BorderRadius.circular(PgTokens.radiusLg),
      ),
      child: Text(message,
          style: const TextStyle(color: PgTokens.colorDanger, fontSize: 13)),
    );
  }
}
