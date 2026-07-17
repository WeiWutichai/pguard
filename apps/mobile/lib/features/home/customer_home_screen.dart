import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../core/controllers/booking_flow_controller.dart';
import '../../core/controllers/customer_avatar_controller.dart';
import '../../core/controllers/customer_home_controller.dart';
import '../../core/controllers/locale_controller.dart';
import '../../core/controllers/notification_controller.dart';
import '../../core/controllers/profile_controller.dart';
import '../../core/controllers/services_controller.dart';
import '../../core/models/booking.dart';
import '../../core/models/chat.dart';
import '../../core/models/money.dart';
import '../../core/models/service_catalog.dart';
import '../../widgets/pg_bottom_nav.dart';
import '../../widgets/pguard_header.dart';
import '../../widgets/primary_button.dart';
import '../auth/widgets/switch_mode_action.dart';
import '../booking/widgets/service_package_card.dart';
import '../chat/chat_routes.dart';
import '../chat/widgets/chat_unread_badge.dart';
import '../notifications/widgets/notification_bell.dart';

/// Customer dashboard (role landing) per the hi-fi design: location-first header with the
/// user's avatar initials, the "บริการ" 4-tile service grid, the "งานที่กำลังดำเนิน" ongoing-job
/// card and the "การจองล่าสุด" recent-booking row — all fed by `GET /v1/bookings` via
/// [CustomerHomeController] (one fetch, pull-to-refresh gesture; no polling).
class CustomerHomeScreen extends ConsumerStatefulWidget {
  const CustomerHomeScreen({super.key});

  /// A booking id to track in the kDebugMode dev tools; overridable for demos via
  /// `--dart-define=PGUARD_DEMO_BOOKING_ID`.
  static const String _demoBookingId = String.fromEnvironment(
    'PGUARD_DEMO_BOOKING_ID',
    defaultValue: '00000000-0000-0000-0000-000000000001',
  );

  @override
  ConsumerState<CustomerHomeScreen> createState() => _CustomerHomeScreenState();
}

class _CustomerHomeScreenState extends ConsumerState<CustomerHomeScreen>
    with WidgetsBindingObserver {
  late final TextEditingController _bookingId =
      TextEditingController(text: CustomerHomeScreen._demoBookingId);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _bookingId.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-pull the customer's bookings on resume so the "งานที่กำลังดำเนิน" ongoing-job card
    // advances (e.g. กำลังค้นหา → รับงานแล้ว) after a guard accepted while the app was backgrounded.
    // invalidate (not refresh()) so it only refetches while this dashboard is mounted/listening —
    // event-driven on resume, NOT a Timer.periodic.
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(customerHomeControllerProvider);
      // Re-pull the notification unread count too: an FCM push that arrived while backgrounded
      // carries a `notification` block, so the in-app onMessage handler never ran and the bell
      // badge is stale on reopen. Invalidate on resume (same event-driven pattern, NOT polling) so
      // the badge catches up without the user first having to open the notification centre.
      ref.invalidate(unreadCountProvider);
    }
  }

  /// Fresh booking via the catalog picker (loading / error / empty fallback for the grid).
  void _startBlankBooking() {
    ref.read(bookingFlowControllerProvider.notifier).reset();
    context.push('/book');
  }

  @override
  Widget build(BuildContext context) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    final bookings = ref.watch(customerHomeControllerProvider).valueOrNull;
    final ongoing =
        bookings == null ? null : CustomerHomeController.ongoing(bookings);
    final latest =
        bookings == null ? null : CustomerHomeController.latest(bookings);
    final address = bookings == null
        ? null
        : CustomerHomeController.recentAddress(bookings);

    return Scaffold(
      backgroundColor: PgTokens.colorBg,
      appBar: PGuardHeader(
        title: 'pguard',
        // Design home header is location-first ("ตำแหน่งปัจจุบัน" over the address); the most
        // recent booking address is the best available stand-in (no saved-places endpoint).
        subtitle: address != null
            ? '${isThai ? 'ตำแหน่งปัจจุบัน' : 'Current location'} · $address'
            : (isThai ? 'ลูกค้า' : 'Customer'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Dual-role accounts only (self-hides otherwise): jump to the mode picker, no logout.
            const SwitchModeAction(),
            const NotificationBell(),
            ChatUnreadBadge(
              acting: ChatRole.customer,
              child: IconButton(
                icon: const Icon(Icons.forum_outlined,
                    color: Colors.white, size: 22),
                tooltip: isThai ? 'แชท' : 'Chat',
                onPressed: () =>
                    context.push(ChatRoutes.list(ChatRole.customer)),
              ),
            ),
            const _ProfileAvatarButton(),
          ],
        ),
      ),
      // Design state 5 (hirer nav + book FAB) — additive chrome; body content unchanged.
      bottomNavigationBar: PgBottomNav(
        tabs: [
          PgNavTab(
            icon: Icons.home_outlined,
            label: isThai ? 'หน้าหลัก' : 'Home',
            active: true,
          ),
          PgNavTab(
            icon: Icons.calendar_today_outlined,
            label: isThai ? 'การจอง' : 'Bookings',
            onTap: () => context.push('/bookings-history'),
          ),
          PgNavTab(
            icon: Icons.account_balance_wallet_outlined,
            label: isThai ? 'กระเป๋า' : 'Wallet',
            onTap: () => context.push('/wallet'),
          ),
          PgNavTab(
            icon: Icons.person_outline,
            label: isThai ? 'โปรไฟล์' : 'Profile',
            onTap: () => context.push('/profile'),
          ),
        ],
        fab: PgNavFab.book(
          label: isThai ? 'เรียก รปภ.' : 'Book',
          onTap: () => context.push('/book'),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () =>
              ref.read(customerHomeControllerProvider.notifier).refresh(),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            // Extra bottom inset keeps the last row clear of the FAB overhang.
            padding: const EdgeInsets.fromLTRB(PgTokens.space4, PgTokens.space4,
                PgTokens.space4, PgTokens.space4 + PgBottomNav.fabOverhang),
            children: [
              _SectionHeading(isThai ? 'บริการ' : 'Services'),
              const SizedBox(height: PgTokens.space3),
              _ServicesGrid(
                isThai: isThai,
                onBrowse: _startBlankBooking,
              ),
              if (ongoing != null) ...[
                const SizedBox(height: PgTokens.space6),
                _SectionHeading(isThai ? 'งานที่กำลังดำเนิน' : 'Ongoing job'),
                const SizedBox(height: PgTokens.space3),
                _OngoingJobCard(booking: ongoing),
              ],
              if (latest != null) ...[
                const SizedBox(height: PgTokens.space6),
                _SectionHeading(isThai ? 'การจองล่าสุด' : 'Latest booking'),
                const SizedBox(height: PgTokens.space2),
                _RecentBookingRow(booking: latest, isThai: isThai),
              ],
              // Dev harness only — no booking-ID input exists anywhere in the design.
              if (kDebugMode) ...[
                const SizedBox(height: PgTokens.space7),
                const _SectionHeading('Dev · track a booking id'),
                const SizedBox(height: PgTokens.space2),
                TextField(
                  controller: _bookingId,
                  decoration: const InputDecoration(labelText: 'Booking ID'),
                ),
                const SizedBox(height: PgTokens.space3),
                PgPrimaryButton(
                  label: isThai ? 'ติดตามงาน' : 'Track active booking',
                  onPressed: () {
                    final id = _bookingId.text.trim();
                    if (id.isNotEmpty) context.push('/booking/$id/live');
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Section heading per the design: 14px weight 600.
class _SectionHeading extends StatelessWidget {
  const _SectionHeading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: PgTokens.colorText),
      );
}

/// The header's profile entry: the user's real profile PHOTO when set, falling back to their
/// initials (or a person icon) on green. `foregroundImage` shows the avatar on top and reverts to
/// the `child` fallback automatically if it is null or fails to load. Still pushes `/profile`.
class _ProfileAvatarButton extends ConsumerWidget {
  const _ProfileAvatarButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    final initials = ref.watch(profileControllerProvider).valueOrNull?.initials;
    final avatarUrl = ref.watch(customerAvatarControllerProvider).valueOrNull;
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
            child: initials == null
                ? const Icon(Icons.person_outline,
                    size: 16, color: Colors.white)
                : Text(
                    initials,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// The "บริการ" list — the FULL admin catalog (`GET /v1/services`) rendered as a vertical list of
/// [ServicePackageCard]s, so the customer PICKS A PACKAGE FIRST (design #67: "ยกรายการนี้มาหน้าแรก
/// แทน รปภ"). Tapping a card opens the package detail (`/book/detail`) — the same destination as the
/// two-screen picker — which then advances to the form → guard. While loading / on error / when
/// empty it degrades to a single tile. Reflects the catalog-fetch state HONESTLY instead of
/// collapsing loading + error + empty all into the book fallback: a spinner while `/services`
/// loads, the package cards once loaded, and — crucially — an AUTO-RETRY when the fetch errors.
/// The cold-start `/services` call can lose the token/network race and error; previously
/// `valueOrNull ?? []` left the home stuck on the "เรียก รปภ." fallback forever even though the
/// picker (a fresh autoDispose watch) loaded the catalog fine. We retry a few times, then offer a
/// manual "ลองใหม่" tile; the genuine-empty case still shows the book fallback.
class _ServicesGrid extends ConsumerStatefulWidget {
  const _ServicesGrid({
    required this.isThai,
    required this.onBrowse,
  });

  final bool isThai;
  final VoidCallback onBrowse;

  @override
  ConsumerState<_ServicesGrid> createState() => _ServicesGridState();
}

class _ServicesGridState extends ConsumerState<_ServicesGrid> {
  static const _maxRetries = 3;
  int _retries = 0;

  /// True while a retry's postFrame invalidate is queued/in flight. The enclosing
  /// CustomerHomeScreen rebuilds on unrelated watches (locale, home controller); without this
  /// guard EVERY such rebuild during the error window would schedule ANOTHER postFrame retry,
  /// burning the retry budget in a burst. Only one retry is ever in flight.
  bool _retryScheduled = false;

  @override
  Widget build(BuildContext context) {
    final isThai = widget.isThai;
    final async = ref.watch(servicesProvider);
    final options = async.valueOrNull ?? const <ServiceOption>[];

    // Loaded with packages → the full-catalog package list. `valueOrNull` retains the last data
    // through a background refresh, so once the catalog shows it never flickers back to a fallback.
    if (options.isNotEmpty) {
      return Column(
        children: [
          for (var i = 0; i < options.length; i++) ...[
            if (i != 0) const SizedBox(height: PgTokens.space3),
            ServicePackageCard(
              service: options[i],
              isThai: isThai,
              // Same destination as the picker — the detail screen advances to the form → guard.
              onTap: () => context.push('/book/detail', extra: options[i]),
              trailing: const Icon(Icons.chevron_right,
                  color: PgTokens.colorTextMuted),
            ),
          ],
        ],
      );
    }

    // No data yet, still in flight → spinner (not the "empty" fallback).
    if (async.isLoading) {
      return _ServiceSpinnerTile(isThai: isThai);
    }

    // Errored with no data → auto-retry a few times (a transient cold-start race), showing a
    // spinner meanwhile; after the cap, a tappable "ลองใหม่" tile.
    if (async.hasError) {
      // Guard with `!_retryScheduled` so only ONE retry is in flight at a time — unrelated parent
      // rebuilds during the error window must not each queue another invalidate.
      if (_retries < _maxRetries && !_retryScheduled) {
        _retryScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted) return;
          _retries += 1;
          await Future<void>.delayed(const Duration(milliseconds: 500));
          if (!mounted) return;
          _retryScheduled = false;
          ref.invalidate(servicesProvider);
        });
        return _ServiceSpinnerTile(isThai: isThai);
      }
      // Still showing the spinner while the queued retry runs; only fall through to the manual
      // tile once the budget is spent AND nothing is in flight.
      if (_retryScheduled) {
        return _ServiceSpinnerTile(isThai: isThai);
      }
      return _ServiceTile(
        label: isThai ? 'ลองใหม่' : 'Retry',
        icon: Icons.refresh,
        onTap: () {
          setState(() => _retries = 0);
          ref.invalidate(servicesProvider);
        },
      );
    }

    // Loaded, genuinely no active services → the book fallback (still a way into the picker).
    return _ServiceTile(
      label: isThai ? 'เรียก รปภ.' : 'Book a guard',
      onTap: widget.onBrowse,
    );
  }
}

/// A "บริการ" grid tile showing a small spinner while the catalog loads / retries — same box as
/// [_ServiceTile] so the row height doesn't jump.
class _ServiceSpinnerTile extends StatelessWidget {
  const _ServiceSpinnerTile({required this.isThai});

  final bool isThai;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
      decoration: BoxDecoration(
        color: PgTokens.colorSurface,
        borderRadius: BorderRadius.circular(PgTokens.radiusXl),
        border: Border.all(color: PgTokens.colorBorder),
      ),
      child: Column(
        children: [
          const SizedBox(
            width: 36,
            height: 36,
            child: Padding(
              padding: EdgeInsets.all(9),
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: PgTokens.colorGreen800,
              ),
            ),
          ),
          const SizedBox(height: PgTokens.space2),
          Text(
            isThai ? 'กำลังโหลด…' : 'Loading…',
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: PgTokens.colorTextMuted,
            ),
          ),
        ],
      ),
    );
  }
}

/// One tile of the "บริการ" grid: 36px icon box on green-50, 11.5px w600 label. The catalog is
/// admin-defined (no per-service icon key), so every tile uses one shared shield icon.
class _ServiceTile extends StatelessWidget {
  const _ServiceTile({
    required this.label,
    required this.onTap,
    this.icon = Icons.shield_outlined,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: PgTokens.colorSurface,
      borderRadius: BorderRadius.circular(PgTokens.radiusXl),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(PgTokens.radiusXl),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(PgTokens.radiusXl),
            border: Border.all(color: PgTokens.colorBorder),
          ),
          child: Column(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: PgTokens.colorGreen50,
                  borderRadius: BorderRadius.circular(PgTokens.radiusLg),
                ),
                child: Icon(icon, size: 18, color: PgTokens.colorGreen800),
              ),
              const SizedBox(height: PgTokens.space2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: PgTokens.colorText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The "งานที่กำลังดำเนิน" card: deep-green surface, white text, right chevron → live status.
class _OngoingJobCard extends StatelessWidget {
  const _OngoingJobCard({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: PgTokens.colorBrand,
      borderRadius: BorderRadius.circular(PgTokens.radius2xl),
      child: InkWell(
        onTap: () => context.push('/booking/${booking.id}/live'),
        borderRadius: BorderRadius.circular(PgTokens.radius2xl),
        child: Padding(
          padding: const EdgeInsets.all(PgTokens.space4),
          child: Row(
            children: [
              // The design's avatar-on-tan slot (no guard name/avatar in the v2 contract,
              // so the brand shield stands in).
              Container(
                width: 38,
                height: 38,
                decoration: const BoxDecoration(
                  color: PgTokens.colorAmber100,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.shield_outlined,
                    size: 18, color: PgTokens.colorAmber700),
              ),
              const SizedBox(width: PgTokens.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      booking.address ?? 'งานรักษาความปลอดภัย',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      BookingLifecycle.labelTh(booking.status),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}

/// The "การจองล่าสุด" row: sunken shield icon, place + date·status, right-aligned total.
class _RecentBookingRow extends StatelessWidget {
  const _RecentBookingRow({required this.booking, required this.isThai});

  final Booking booking;
  final bool isThai;

  @override
  Widget build(BuildContext context) {
    final when = booking.scheduledAt;
    final dateStatus = [
      if (when != null) thaiShortDate(when, isThai: isThai),
      isThai
          ? BookingLifecycle.labelTh(booking.status)
          : BookingLifecycle.labelEn(booking.status),
    ].join(' · ');
    final total = bookingTotalSatang(booking);
    return InkWell(
      onTap: () => context.push('/booking/${booking.id}/live'),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: PgTokens.space3),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: PgTokens.colorBorder)),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: PgTokens.colorSunken,
                borderRadius: BorderRadius.circular(PgTokens.radiusLg),
              ),
              child: const Icon(Icons.shield_outlined,
                  size: 18, color: PgTokens.colorTextMuted),
            ),
            const SizedBox(width: PgTokens.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    booking.address ?? '—',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    dateStatus,
                    style: const TextStyle(
                        fontSize: 11.5, color: PgTokens.colorTextMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: PgTokens.space2),
            if (total > 0)
              Text(
                Money.format(total),
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
          ],
        ),
      ),
    );
  }
}
