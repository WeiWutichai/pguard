import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../core/controllers/guard_avatar_controller.dart';
import '../../core/controllers/guard_jobs_controller.dart';
import '../../core/controllers/guard_ratings_controller.dart';
import '../../core/controllers/locale_controller.dart';
import '../../core/controllers/notification_controller.dart';
import '../../core/controllers/profile_controller.dart';
import '../../core/controllers/session_controller.dart';
import '../../core/controllers/tracking_controller.dart';
import '../../core/models/booking.dart';
import '../../core/models/chat.dart';
import '../../core/models/geo.dart';
import '../../core/controllers/earnings.dart';
import '../../core/controllers/guard_earnings_controller.dart';
import '../../core/models/money.dart';
import '../../core/network/api_error_l10n.dart';
import '../../core/network/api_exception.dart';
import '../../widgets/pg_bottom_nav.dart';
import '../../widgets/pguard_header.dart';
import '../../widgets/primary_button.dart';
import '../auth/widgets/switch_mode_action.dart';
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

class _GuardHomeScreenState extends ConsumerState<GuardHomeScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Cheap safety net: re-fetch the guard's jobs when the app comes back to the foreground, so a
    // "new_job" push that was missed while backgrounded still surfaces the offer. invalidate (not
    // refresh()) so it only refetches while this dashboard is mounted/listening.
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(guardJobsControllerProvider);
      // Also re-pull the notification unread count: a backgrounded FCM push carries a
      // `notification` block so the in-app handler never ran and the bell badge is stale on reopen.
      // Invalidate on resume (event-driven, NOT polling) so the badge catches up without a tap.
      ref.invalidate(unreadCountProvider);
      // Belt-and-suspenders for the live rating card: a `rating.submitted` push delivered while
      // backgrounded/terminated never ran the in-app handler, so re-pull the guard's ratings on
      // resume too. Family-wide invalidate (re-pulls the mounted own-id instance). NOT polling.
      ref.invalidate(guardRatingsProvider);
    }
  }

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
            // Dual-role accounts only (self-hides otherwise): jump to the mode picker, no logout.
            const SwitchModeAction(),
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
            _GuardProfileAvatarButton(isThai: isThai),
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
                      ? localizeApiError(isThai, e)
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
              : const Icon(Icons.person_outline, color: PgTokens.colorGreen800),
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

  /// Today's earnings in satang — the SAME number the earnings screen shows.
  ///
  /// This deliberately delegates to [GuardEarnings.jobEarningsSatang] instead of computing a total
  /// of its own. It used to be `base_fee × hours × guard_count` over completed AND in-progress
  /// jobs, which overstated pay three ways: `guard_count` is how many guards the CUSTOMER hired
  /// (this guard is paid for one of them, not the whole crew), an unfinished job is money not yet
  /// earned, and booked hours are an estimate the reconciliation can lower. The home card and the
  /// earnings screen therefore disagreed on the same day's pay.
  ///
  /// [actualHours] comes from `GET /payments/earnings` (the hours actually worked, persisted at
  /// reconciliation); without it each job falls back to its booked hours.
  static int earningsTodaySatang(
    List<Booking> all,
    DateTime now, {
    Map<String, double>? actualHours,
  }) {
    var sum = 0;
    for (final b in GuardEarnings.completedJobs(all)) {
      if (!_isToday(b.scheduledAt, now)) continue;
      sum += GuardEarnings.jobEarningsSatang(b, actualHours: actualHours);
    }
    return sum;
  }

  /// Number of jobs THIS GUARD is working today.
  ///
  /// The feed behind this screen is `[...open, ...assigned]` — open jobs are unassigned requests
  /// from the discovery feed that belong to no guard yet. Counting the whole list made the number
  /// climb whenever any customer booked, before this guard had accepted anything. `stepIndex >= 0`
  /// admits exactly `accepted → completed` and excludes `requested` (not taken) along with
  /// `cancelled`/`declined` (not worked).
  static int jobsToday(List<Booking> all, DateTime now) => all
      .where((b) =>
          BookingLifecycle.stepIndex(b.status) >= 0 &&
          _isToday(b.scheduledAt, now))
      .length;

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

/// The header's profile entry: the guard's real profile PHOTO when set, falling back to a person
/// icon on green. `foregroundImage` shows the avatar on top and reverts to the `child` fallback if
/// it is null or fails to load. Pushes `/profile` (mirrors the customer header avatar).
class _GuardProfileAvatarButton extends ConsumerWidget {
  const _GuardProfileAvatarButton({required this.isThai});

  final bool isThai;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final avatarUrl = ref.watch(guardAvatarControllerProvider).valueOrNull;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: PgTokens.space1),
      child: Tooltip(
        message: isThai ? 'โปรไฟล์' : 'Profile',
        child: InkWell(
          onTap: () => context.push('/profile'),
          customBorder: const CircleBorder(),
          child: CircleAvatar(
            radius: 16,
            backgroundColor: PgTokens.colorGreen800,
            foregroundImage: (avatarUrl != null && avatarUrl.isNotEmpty)
                ? NetworkImage(avatarUrl)
                : null,
            child:
                const Icon(Icons.person_outline, size: 16, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

/// Screen 1 stats row — 3 equal cards: today's earnings / jobs today / rating.
class _StatsRow extends ConsumerWidget {
  const _StatsRow({required this.bookings, required this.isThai});

  final List<Booking> bookings;
  final bool isThai;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    // Same source as the earnings screen — hours ACTUALLY worked, so the two screens agree.
    final actualHours =
        ref.watch(guardEarningsHoursProvider).valueOrNull ?? const {};
    // Bound the row's height: CrossAxisAlignment.stretch (equal-height cards) needs a FINITE
    // height, but this Row sits directly in a ListView (UNBOUNDED height). Without IntrinsicHeight
    // the constraint is h=∞ → in release (asserts off) the row grows unbounded and pushes the jobs
    // sections below it OFF-SCREEN (the home looked "empty"); debug throws a RenderFlex assert.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _StatCard(
              value: Money.format(GuardHomeStats.earningsTodaySatang(
                  bookings, now,
                  actualHours: actualHours)),
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
      ),
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
      // Design `.summary-card` (bento): 16px padding, 12px corners, centered, soft elevation.
      padding: const EdgeInsets.all(PgTokens.space4),
      decoration: BoxDecoration(
        color: PgTokens.colorSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: PgTokens.colorBorder),
        boxShadow: const [
          BoxShadow(
              color: Color(0x0A000000), blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Bold centered value with tabular figures so the three cards' numerals align.
          Text(value,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w700,
                  color: PgTokens.colorText,
                  fontFeatures: [FontFeature.tabularFigures()])),
          const SizedBox(height: 4),
          Text(label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: PgTokens.colorTextMuted)),
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
              booking: b,
              isThai: isThai,
              // Badge a `pending_completion` job (awaiting the customer) and open it READ-ONLY —
              // it's in the active list but the guard can't re-end it; the customer confirms.
              statusLabel: GuardJobsController.statusBadge(b, isThai: isThai),
              onTap: () => GuardJobsController.opensReadOnly(b)
                  ? onOpenDetail(b.id)
                  : onOpenActive(b.id),
            ),
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
                    // 96px so the longer "ไม่รับงาน" label clears the TextButton padding.
                    width: 96,
                    child: PgGhostButton(
                      label: isThai ? 'ไม่รับงาน' : 'Decline',
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
  Widget build(BuildContext context) => _EmptyJobsCard(
        icon: Icons.pending_actions_outlined,
        text: isThai ? 'ยังไม่มีงานที่กำลังทำ' : 'No active jobs yet',
        minHeight: 100,
      );
}

class _EmptyIncoming extends StatelessWidget {
  const _EmptyIncoming({required this.isThai});

  final bool isThai;

  @override
  Widget build(BuildContext context) => _EmptyJobsCard(
        icon: Icons.work_history_outlined,
        text: isThai
            ? 'ยังไม่มีงานใหม่ — เปิดสถานะออนไลน์เพื่อรับงาน'
            : 'No new jobs — go online to receive offers',
        minHeight: 120,
        badge: true,
      );
}

/// Design empty-state: a dashed "drop-zone" card — centered icon (a raised circular badge for the
/// incoming feed) over a muted message. Mirrors the `.border-dashed` empty blocks in the mockup.
class _EmptyJobsCard extends StatelessWidget {
  const _EmptyJobsCard({
    required this.icon,
    required this.text,
    required this.minHeight,
    this.badge = false,
  });

  final IconData icon;
  final String text;
  final double minHeight;
  final bool badge;

  @override
  Widget build(BuildContext context) {
    final Widget glyph = badge
        ? Container(
            padding: const EdgeInsets.all(14),
            decoration: const BoxDecoration(
              color: PgTokens.colorSurface,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                    color: Color(0x14000000),
                    blurRadius: 8,
                    offset: Offset(0, 2)),
              ],
            ),
            child: Icon(icon, size: 30, color: PgTokens.colorGreen600),
          )
        : Icon(icon, size: 40, color: PgTokens.colorTextFaint);
    return CustomPaint(
      foregroundPainter:
          _DashedRRectPainter(color: PgTokens.colorBorderStrong, radius: 12),
      child: Container(
        width: double.infinity,
        constraints: BoxConstraints(minHeight: minHeight),
        padding: const EdgeInsets.all(PgTokens.space5),
        decoration: BoxDecoration(
          color: PgTokens.colorBg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            glyph,
            const SizedBox(height: 10),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: PgTokens.colorTextMuted, fontSize: 13.5),
            ),
          ],
        ),
      ),
    );
  }
}

/// Paints a dashed rounded-rectangle border on the edge of its child (Flutter has no built-in
/// dashed border). Used by the empty-state "drop-zone" cards.
class _DashedRRectPainter extends CustomPainter {
  _DashedRRectPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3;
    final path = Path()
      ..addRRect(
          RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)));
    const dash = 5.0;
    const gap = 4.0;
    for (final metric in path.computeMetrics()) {
      var dist = 0.0;
      while (dist < metric.length) {
        final next = (dist + dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(dist, next), paint);
        dist = next + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRRectPainter old) =>
      old.color != color || old.radius != radius;
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
