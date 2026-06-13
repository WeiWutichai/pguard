import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../core/controllers/booking_flow_controller.dart';
import '../../core/controllers/customer_home_controller.dart';
import '../../core/controllers/locale_controller.dart';
import '../../core/controllers/profile_controller.dart';
import '../../core/models/booking.dart';
import '../../core/models/chat.dart';
import '../../core/models/money.dart';
import '../../core/models/service_catalog.dart';
import '../../widgets/pg_bottom_nav.dart';
import '../../widgets/pguard_header.dart';
import '../../widgets/primary_button.dart';
import '../booking/service_selection_screen.dart' show serviceIcon;
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

class _CustomerHomeScreenState extends ConsumerState<CustomerHomeScreen> {
  late final TextEditingController _bookingId =
      TextEditingController(text: CustomerHomeScreen._demoBookingId);

  @override
  void dispose() {
    _bookingId.dispose();
    super.dispose();
  }

  void _startBooking(SecurityService service) {
    ref.read(bookingFlowControllerProvider.notifier)
      ..reset()
      ..selectService(service);
    context.push('/book/form');
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
            ? 'ตำแหน่งปัจจุบัน · $address'
            : 'ลูกค้า · Customer',
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
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
              Row(
                children: [
                  for (final service in SecurityService.values) ...[
                    Expanded(
                      child: _ServiceTile(
                        service: service,
                        onTap: () => _startBooking(service),
                      ),
                    ),
                    if (service != SecurityService.values.last)
                      const SizedBox(width: PgTokens.space2),
                  ],
                ],
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
                _RecentBookingRow(booking: latest),
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

/// The header's profile entry: the user's avatar initials (no avatar endpoint exists in v2),
/// white on green, still pushing `/profile`.
class _ProfileAvatarButton extends ConsumerWidget {
  const _ProfileAvatarButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    final initials = ref.watch(profileControllerProvider).valueOrNull?.initials;
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

/// One tile of the "บริการ" grid: 36px icon box on green-50, 11.5px w600 label.
class _ServiceTile extends StatelessWidget {
  const _ServiceTile({required this.service, required this.onTap});

  final SecurityService service;
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
                child: Icon(serviceIcon(service),
                    size: 18, color: PgTokens.colorGreen800),
              ),
              const SizedBox(height: PgTokens.space2),
              Text(
                service.labelTh,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
  const _RecentBookingRow({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context) {
    final when = booking.scheduledAt;
    final dateStatus = [
      if (when != null) thaiShortDate(when),
      BookingLifecycle.labelTh(booking.status),
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
