import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../core/controllers/guard_jobs_controller.dart';
import '../../core/controllers/locale_controller.dart';
import '../../core/controllers/tracking_controller.dart';
import '../../core/models/booking.dart';
import '../../core/models/chat.dart';
import '../../core/models/money.dart';
import '../../core/network/api_exception.dart';
import '../../widgets/pg_bottom_nav.dart';
import '../../widgets/pguard_header.dart';
import '../../widgets/primary_button.dart';
import '../chat/chat_routes.dart';
import '../chat/widgets/chat_unread_badge.dart';
import '../guard/widgets/job_card.dart';
import '../guard/widgets/online_card.dart';
import '../notifications/widgets/notification_bell.dart';

/// Guard dashboard (role landing): online/standby GPS toggle + the guard's jobs (incoming to
/// accept, active to work). UI per `Mobile - Guard App.html` / `Mobile - Active Standby.html`.
class GuardHomeScreen extends ConsumerStatefulWidget {
  const GuardHomeScreen({super.key});

  @override
  ConsumerState<GuardHomeScreen> createState() => _GuardHomeScreenState();
}

class _GuardHomeScreenState extends ConsumerState<GuardHomeScreen> {
  /// Anchors the jobs section so the "งาน / Jobs" tab can scroll to it — the jobs list
  /// *is* this screen's content (v2 has no separate jobs route).
  final GlobalKey _jobsKey = GlobalKey();

  Future<void> _accept(String id) async {
    final err = await ref.read(guardJobsControllerProvider.notifier).accept(id);
    if (!mounted) return;
    if (err != null) {
      _snack(context, err);
    } else {
      context.push('/guard/active/$id');
    }
  }

  // First-come-accept: an unaccepted offer can't be "declined" server-side — just hide it.
  void _dismiss(String id) =>
      ref.read(guardJobsControllerProvider.notifier).dismiss(id);

  static void _snack(BuildContext context, String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  void _scrollToJobs() {
    final jobsContext = _jobsKey.currentContext;
    // Jobs not loaded yet — nothing to scroll to.
    if (jobsContext == null) {
      return;
    }
    Scrollable.ensureVisible(jobsContext,
        duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    final jobs = ref.watch(guardJobsControllerProvider);
    // Duty FAB mirrors the same controller the OnlineCard switch drives.
    final online =
        ref.watch(trackingControllerProvider.select((s) => s.online));
    final incomingCount =
        GuardJobsController.incoming(jobs.valueOrNull ?? const <Booking>[])
            .length;

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
                tooltip: isThai ? 'แชท' : 'Chat',
                onPressed: () => context.push(ChatRoutes.list(ChatRole.guard)),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.person_outline,
                  color: Colors.white, size: 22),
              tooltip: isThai ? 'โปรไฟล์' : 'Profile',
              onPressed: () => context.push('/profile'),
            ),
          ],
        ),
      ),
      // Design state 4 (guard nav + duty FAB) — additive chrome; body content unchanged.
      bottomNavigationBar: PgBottomNav(
        tabs: [
          PgNavTab(
            icon: Icons.home_outlined,
            label: isThai ? 'หน้าหลัก' : 'Home',
            active: true,
          ),
          PgNavTab(
            icon: Icons.inbox_outlined,
            label: isThai ? 'งาน' : 'Jobs',
            badgeCount: incomingCount,
            onTap: _scrollToJobs,
          ),
          PgNavTab(
            icon: Icons.payments_outlined,
            label: isThai ? 'รายได้' : 'Earnings',
            onTap: () => context.push('/earnings'),
          ),
          PgNavTab(
            icon: Icons.person_outline,
            label: isThai ? 'โปรไฟล์' : 'Profile',
            onTap: () => context.push('/profile'),
          ),
        ],
        fab: online
            ? PgNavFab.onDuty(
                label: isThai ? 'พร้อมรับงาน' : 'On duty',
                onTap: () =>
                    ref.read(trackingControllerProvider.notifier).toggle(),
              )
            : PgNavFab.offline(
                label: isThai ? 'ออฟไลน์' : 'Offline',
                onTap: () =>
                    ref.read(trackingControllerProvider.notifier).toggle(),
              ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () =>
              ref.read(guardJobsControllerProvider.notifier).refresh(),
          child: ListView(
            // Extra bottom inset keeps the last card clear of the FAB overhang.
            padding: const EdgeInsets.fromLTRB(PgTokens.space4, PgTokens.space4,
                PgTokens.space4, PgTokens.space4 + PgBottomNav.fabOverhang),
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
                      : isThai
                          ? 'โหลดงานไม่สำเร็จ'
                          : 'Could not load jobs',
                ),
                data: (all) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _StatsRow(bookings: all, isThai: isThai),
                    const SizedBox(height: PgTokens.space4),
                    _JobsBody(
                      key: _jobsKey,
                      isThai: isThai,
                      incoming: GuardJobsController.incoming(all),
                      active: GuardJobsController.active(all),
                      onAccept: _accept,
                      onDismiss: _dismiss,
                      onOpenActive: (id) => context.push('/guard/active/$id'),
                      onOpenDetail: (id) => context.push('/guard/job/$id'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pure derivations for the dashboard stat cards (Screen 1 "Stats cards"). Static + widget-free
/// so they are unit-testable. NOTE: the design's fix sketch put these on GuardJobsController,
/// but `core/controllers` is outside this slice's ownership — the pure logic lives here instead.
class GuardHomeStats {
  const GuardHomeStats._();

  static bool _isToday(DateTime? scheduledAt, DateTime now) {
    final local = scheduledAt?.toLocal();
    return local != null &&
        local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
  }

  /// Today's earnings in satang: Σ base_fee × hours × guard_count over the guard's
  /// completed/active jobs scheduled today.
  static int earningsTodaySatang(List<Booking> all, DateTime now) {
    var sum = 0;
    for (final b in all) {
      final earns = b.status == BookingStatus.completed ||
          BookingLifecycle.isActive(b.status);
      if (!earns || !_isToday(b.scheduledAt, now)) continue;
      sum += Money.total(
        baseFeeSatang: Money.satangFromString(b.baseFee),
        hours: b.hours ?? 0,
        guardCount: b.guardCount ?? 1,
      );
    }
    return sum;
  }

  /// Number of the guard's jobs scheduled today.
  static int jobsToday(List<Booking> all, DateTime now) =>
      all.where((b) => _isToday(b.scheduledAt, now)).length;
}

/// Screen 1 stats row — 3 equal cards: today's earnings / jobs today / rating.
class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.bookings, required this.isThai});

  final List<Booking> bookings;
  final bool isThai;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _StatCard(
            value:
                Money.format(GuardHomeStats.earningsTodaySatang(bookings, now)),
            label: isThai ? 'รายได้วันนี้' : 'Today',
          ),
        ),
        const SizedBox(width: PgTokens.space3),
        Expanded(
          child: _StatCard(
            value: '${GuardHomeStats.jobsToday(bookings, now)}',
            label: isThai ? 'งานวันนี้' : 'Jobs',
          ),
        ),
        const SizedBox(width: PgTokens.space3),
        // Rating stays a placeholder until GET /v1/guards/{id}/ratings stats is wired.
        Expanded(
          child: _StatCard(value: '—', label: isThai ? 'คะแนน' : 'Rating'),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(PgTokens.space3),
      decoration: BoxDecoration(
        color: PgTokens.colorSurface,
        borderRadius: BorderRadius.circular(PgTokens.radius2xl),
        border: Border.all(color: PgTokens.colorBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w600,
                  color: PgTokens.colorText,
                  fontFeatures: [FontFeature.tabularFigures()])),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(
                  fontSize: 11, color: PgTokens.colorTextMuted)),
        ],
      ),
    );
  }
}

class _JobsBody extends StatelessWidget {
  const _JobsBody({
    super.key,
    required this.isThai,
    required this.incoming,
    required this.active,
    required this.onAccept,
    required this.onDismiss,
    required this.onOpenActive,
    required this.onOpenDetail,
  });

  final bool isThai;
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
          _SectionHeader(isThai ? 'งานที่กำลังทำ' : 'Active'),
          for (final b in active) ...[
            GuardJobCard(booking: b, onTap: () => onOpenActive(b.id)),
            const SizedBox(height: PgTokens.space3),
          ],
        ],
        _SectionHeader(isThai
            ? (incoming.isEmpty
                ? 'งานรอตอบรับ'
                : 'งานรอตอบรับ ${incoming.length}')
            : (incoming.isEmpty ? 'Incoming' : 'Incoming ${incoming.length}')),
        if (incoming.isEmpty)
          _EmptyIncoming(isThai: isThai)
        else
          for (final b in incoming) ...[
            GuardJobCard(
              booking: b,
              highlight: true,
              onTap: () => onOpenDetail(b.id),
              actions: Row(
                children: [
                  SizedBox(
                    width: 80,
                    child: PgGhostButton(
                      label: isThai ? 'ข้าม' : 'Skip',
                      onPressed: () => onDismiss(b.id),
                    ),
                  ),
                  const SizedBox(width: PgTokens.space2),
                  Expanded(
                    child: PgPrimaryButton(
                      label: isThai ? 'รับงาน' : 'Accept',
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
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      );
}

class _EmptyIncoming extends StatelessWidget {
  const _EmptyIncoming({required this.isThai});

  final bool isThai;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(PgTokens.space4),
      decoration: BoxDecoration(
        color: PgTokens.colorSurface,
        borderRadius: BorderRadius.circular(PgTokens.radiusLg),
        border: Border.all(color: PgTokens.colorBorder),
      ),
      child: Text(
        isThai
            ? 'ยังไม่มีงานใหม่ — เปิดสถานะออนไลน์เพื่อรับงาน'
            : 'No new jobs — go online to receive offers',
        style: const TextStyle(color: PgTokens.colorTextMuted, fontSize: 13),
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
