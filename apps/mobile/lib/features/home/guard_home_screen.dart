import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../core/controllers/guard_jobs_controller.dart';
import '../../core/controllers/guard_ratings_controller.dart';
import '../../core/controllers/locale_controller.dart';
import '../../core/controllers/profile_controller.dart';
import '../../core/controllers/session_controller.dart';
import '../../core/controllers/tracking_controller.dart';
import '../../core/models/booking.dart';
import '../../core/models/chat.dart';
import '../../core/models/geo.dart';
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
        subtitle: isThai ? 'เจ้าหน้าที่' : 'Guard',
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
            onTap: () => context.push('/guard/jobs'),
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
              const _GreetingHeader(),
              const SizedBox(height: PgTokens.space4),
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

/// Design `.greet`: a 44px avatar (guard initials) + a time-of-day greeting and the guard's name,
/// read once from the cached profile (`profileControllerProvider`, no polling). Degrades to a
/// generic role label + person glyph when the name isn't available yet (loading / 404 / no name).
class _GreetingHeader extends ConsumerWidget {
  const _GreetingHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    final name =
        ref.watch(profileControllerProvider).valueOrNull?.fullName?.trim();
    final hasName = name != null && name.isNotEmpty;
    final initials = hasName ? _initialsOf(name) : null;
    return Row(
      children: [
        CircleAvatar(
          radius: 22,
          backgroundColor: PgTokens.colorGreen100,
          child: initials != null
              ? Text(initials,
                  style: const TextStyle(
                      color: PgTokens.colorGreen800,
                      fontWeight: FontWeight.w600))
              : const Icon(Icons.person_outline,
                  color: PgTokens.colorGreen800),
        ),
        const SizedBox(width: PgTokens.space3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_greeting(isThai),
                  style: const TextStyle(
                      fontSize: 12.5, color: PgTokens.colorTextMuted)),
              const SizedBox(height: 2),
              Text(hasName ? name : (isThai ? 'เจ้าหน้าที่' : 'Guard'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ],
    );
  }

  static String _greeting(bool isThai) {
    final h = DateTime.now().hour;
    if (h < 11) return isThai ? 'สวัสดีตอนเช้า' : 'Good morning';
    if (h < 13) return isThai ? 'สวัสดีตอนสาย' : 'Good day';
    if (h < 17) return isThai ? 'สวัสดีตอนบ่าย' : 'Good afternoon';
    return isThai ? 'สวัสดีตอนเย็น' : 'Good evening';
  }

  /// Design `.greet .av`: the first one-or-two characters of the given name (e.g. "สมชาย" → "สม").
  static String? _initialsOf(String name) {
    final parts =
        name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return null;
    final first = parts.first;
    return first.length >= 2 ? first.substring(0, 2) : first.substring(0, 1);
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

  /// HONEST guard→job-site distance+ETA label for the incoming card, or `null` when it can't be
  /// shown truthfully. Straight-line [TravelEstimate] (the `~` marks the ETA approximate — no
  /// routing service) computed ONLY when BOTH the guard's latest GPS fix [guardAt] AND the
  /// booking's pinned coordinate exist; `null` otherwise (offline / no fix / no pin) so the card
  /// omits the line rather than fabricating a distance. Pure → unit-testable without widgets.
  static String? incomingDistanceLabel(
    GeoPoint? guardAt,
    Booking booking, {
    required bool isThai,
  }) {
    final lat = booking.lat;
    final lng = booking.lng;
    if (guardAt == null || lat == null || lng == null) return null;
    final est = TravelEstimate.between(guardAt, GeoPoint(lat, lng));
    return '${est.distanceLabel(isThai)} · ${est.etaLabel(isThai)}';
  }
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
        Expanded(child: _RatingStatCard(isThai: isThai)),
      ],
    );
  }
}

/// The rating stat card — the guard's real overall average from `GET /v1/guards/{id}/ratings`
/// (tap → the full "รีวิวที่ได้รับ" screen). Shows "—" while loading / on error / with no reviews
/// (never a fake 0.0).
class _RatingStatCard extends ConsumerWidget {
  const _RatingStatCard({required this.isThai});

  final bool isThai;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final guardId = ref.watch(sessionProvider.select((s) => s.user?.userId));
    final value = guardId == null
        ? '—'
        : ref.watch(guardRatingsProvider(guardId)).maybeWhen(
              data: (r) =>
                  r.hasRatings ? '${r.averageValue!.toStringAsFixed(1)}★' : '—',
              orElse: () => '—',
            );
    return InkWell(
      onTap: guardId == null ? null : () => context.push('/guard/ratings'),
      borderRadius: BorderRadius.circular(PgTokens.radius2xl),
      child: _StatCard(value: value, label: isThai ? 'คะแนน' : 'Rating'),
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
      // Design `.gstat .s`: 13px padding, 16px corners.
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: PgTokens.colorSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: PgTokens.colorBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Design `.gstat .v`: the mono numeric face (matches the job-card / online-card numerals).
          Text(value,
              style: const TextStyle(
                  fontFamily: 'IBMPlexMono',
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
        // Always surface BOTH the in-progress and incoming sections (each with an empty state),
        // so the dashboard's middle shows the guard's work even before any job lands.
        _SectionHeader(
          isThai ? 'งานที่กำลังทำ' : 'Active',
          onSeeAll: () => context.push('/guard/jobs'),
          seeAllLabel: isThai ? 'ดูทั้งหมด' : 'See all',
        ),
        if (active.isEmpty)
          _EmptyActive(isThai: isThai)
        else
          for (final b in active) ...[
            GuardJobCard(
                booking: b, isThai: isThai, onTap: () => onOpenActive(b.id)),
            const SizedBox(height: PgTokens.space3),
          ],
        const SizedBox(height: PgTokens.space4),
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
              isThai: isThai,
              highlight: true,
              onTap: () => onOpenDetail(b.id),
              infoLine: _GuardDistanceLine(booking: b, isThai: isThai),
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

/// The guard→job-site distance + ~ETA line on an incoming card (design `.sb-line`: pin · "0.8
/// กม. · ~4 นาที"). HONEST data only: straight-line haversine via the shared [TravelEstimate]
/// (the `~` marks the ETA approximate — there is no routing service), shown ONLY when the guard's
/// live GPS fix AND the booking's pinned coordinate both exist; otherwise it renders nothing
/// (never a fabricated distance/ETA). Watches just the latest fix, so only THIS line rebuilds as
/// the guard moves — not the whole dashboard.
class _GuardDistanceLine extends ConsumerWidget {
  const _GuardDistanceLine({required this.booking, required this.isThai});

  final Booking booking;
  final bool isThai;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sample =
        ref.watch(trackingControllerProvider.select((s) => s.lastSample));
    final guardAt = sample == null ? null : GeoPoint(sample.lat, sample.lng);
    final label =
        GuardHomeStats.incomingDistanceLabel(guardAt, booking, isThai: isThai);
    // No live fix (offline / no GPS) or no pinned job coordinate → omit the line entirely.
    if (label == null) return const SizedBox.shrink();
    return Row(
      children: [
        const Icon(Icons.place_outlined,
            size: 14, color: PgTokens.colorTextMuted),
        const SizedBox(width: PgTokens.space1),
        Text(
          label,
          style:
              const TextStyle(fontSize: 12.5, color: PgTokens.colorTextMuted),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text, {this.onSeeAll, this.seeAllLabel});
  final String text;

  /// Optional trailing "see all" link (design `.sec-h .more`) — a brand-green link pushed right.
  final VoidCallback? onSeeAll;
  final String? seeAllLabel;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: PgTokens.space2),
        child: Row(
          children: [
            Expanded(
              child: Text(text,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600)),
            ),
            if (onSeeAll != null)
              InkWell(
                onTap: onSeeAll,
                child: Text(
                  seeAllLabel ?? 'ดูทั้งหมด',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: PgTokens.colorGreen500,
                  ),
                ),
              ),
          ],
        ),
      );
}

class _EmptyActive extends StatelessWidget {
  const _EmptyActive({required this.isThai});

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
            ? 'ยังไม่มีงานที่กำลังทำ'
            : 'No active jobs yet',
        style: const TextStyle(color: PgTokens.colorTextMuted, fontSize: 13),
      ),
    );
  }
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
