import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../core/controllers/bookings_history.dart';
import '../../core/controllers/customer_home_controller.dart';
import '../../core/controllers/locale_controller.dart';
import '../../core/models/booking.dart';
import '../../core/models/money.dart';
import '../../core/network/api_exception.dart';
import '../../widgets/pg_error_state.dart';
import '../../widgets/pg_skeleton.dart';
import '../../widgets/pguard_header.dart';

/// Customer "การจอง" tab — the caller's bookings from `GET /v1/bookings` (customer = the
/// bookings they created, server-ordered newest first). UI per More_Screens.md Screen 5
/// "Hirer History": segmented filter chips + history rows (icon badge / address / date·status /
/// status badge + mono amount). Tap → the booking's live-status screen. Shares
/// [customerHomeControllerProvider] with the dashboard (same endpoint — one cache, no
/// duplicate fetch); pull-to-refresh re-pulls, no polling.
///
/// Design deltas (data the v2 contract doesn't carry — never invented):
///  - row title is the booking ADDRESS (the mock shows "guard name · service"; bookings have
///    neither a guard name nor a service type);
///  - the done rows' "★ 5.0" rating is omitted (no rating field on a booking);
///  - cancelled rows show the booked total muted (the mock's "฿0 · คืนเงินแล้ว" is the
///    payment service's knowledge, not the booking's).
class BookingsListScreen extends ConsumerStatefulWidget {
  const BookingsListScreen({super.key});

  @override
  ConsumerState<BookingsListScreen> createState() => _BookingsListScreenState();
}

class _BookingsListScreenState extends ConsumerState<BookingsListScreen> {
  BookingsHistoryFilter _filter = BookingsHistoryFilter.all;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(customerHomeControllerProvider);
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;

    return Scaffold(
      backgroundColor: PgTokens.colorBg,
      appBar: PGuardHeader(
        light: true,
        title: isThai ? 'ประวัติการจ้าง' : 'Hirer history',
        subtitle: isThai ? 'รายการจองทั้งหมดของคุณ' : 'All your bookings',
        showBack: true,
      ),
      // Stale-while-revalidate (perf-review #1): the last-known bookings via `valueOrNull` (shared
      // with the dashboard — arriving from Home is an instant cache hit), the filter chips + a
      // skeleton list on a genuine first load, and the error state only with no data.
      body: SafeArea(
        child: Builder(builder: (context) {
          final all = async.valueOrNull;
          if (all == null) {
            if (async.hasError) {
              return PgErrorState(
                title: isThai
                    ? 'โหลดประวัติการจ้างไม่สำเร็จ'
                    : 'Could not load history',
                message: async.error is ApiException
                    ? (async.error as ApiException).message
                    : null,
                onRetry: () =>
                    ref.read(customerHomeControllerProvider.notifier).refresh(),
              );
            }
            return ListView(
              children: [
                _FilterChips(
                  selected: _filter,
                  isThai: isThai,
                  onSelect: (f) => setState(() => _filter = f),
                ),
                const Padding(
                  padding: EdgeInsets.all(PgTokens.space4),
                  child: PgSkeletonList(count: 5, itemHeight: 64),
                ),
              ],
            );
          }
          {
            final filtered = BookingsHistory.filter(all, _filter);
            return RefreshIndicator(
              onRefresh: () =>
                  ref.read(customerHomeControllerProvider.notifier).refresh(),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  _FilterChips(
                    selected: _filter,
                    isThai: isThai,
                    onSelect: (f) => setState(() => _filter = f),
                  ),
                  if (all.isEmpty)
                    _EmptyHistory(isThai: isThai)
                  else if (filtered.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(PgTokens.space6),
                      child: Center(
                        child: Text(
                          isThai
                              ? 'ไม่มีรายการในหมวดนี้'
                              : 'Nothing in this filter',
                          style: const TextStyle(
                              fontSize: 13, color: PgTokens.colorTextMuted),
                        ),
                      ),
                    )
                  else
                    for (final b in filtered)
                      _HistoryRow(booking: b, isThai: isThai),
                ],
              ),
            );
          }
        }),
      ),
    );
  }
}

/// The design's `.hist-tabs` segmented chips: 12.5px w600, sunken bg; active = green-900
/// (colorBrand) with white text.
class _FilterChips extends StatelessWidget {
  const _FilterChips({
    required this.selected,
    required this.isThai,
    required this.onSelect,
  });

  final BookingsHistoryFilter selected;
  final bool isThai;
  final ValueChanged<BookingsHistoryFilter> onSelect;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(
          PgTokens.space5, PgTokens.space3, PgTokens.space5, PgTokens.space3),
      child: Row(
        children: [
          for (final f in BookingsHistoryFilter.values) ...[
            _Chip(
              label: f.label(isThai),
              active: f == selected,
              onTap: () => onSelect(f),
            ),
            if (f != BookingsHistoryFilter.values.last)
              const SizedBox(width: PgTokens.space1),
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? PgTokens.colorBrand : PgTokens.colorSunken,
      borderRadius: BorderRadius.circular(PgTokens.radiusLg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(PgTokens.radiusLg),
        child: Padding(
          // Design `.hist-tab`: padding 7px 13px.
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: active ? Colors.white : PgTokens.colorTextMuted,
            ),
          ),
        ),
      ),
    );
  }
}

/// One `.hist-row`: 40px icon badge + address/status + badge & mono amount, hairline divider.
class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.booking, required this.isThai});

  final Booking booking;
  final bool isThai;

  @override
  Widget build(BuildContext context) {
    final badge = BookingsHistory.badge(booking.status);
    final when = booking.scheduledAt;
    final statusLine = [
      if (when != null) thaiShortDate(when, isThai: isThai),
      isThai
          ? BookingLifecycle.labelTh(booking.status)
          : BookingLifecycle.labelEn(booking.status),
    ].join(' · ');
    final total = bookingTotalSatang(booking);
    final cancelled = badge == HistoryBadge.cancelled;

    return InkWell(
      onTap: () => context.push('/booking/${booking.id}/live'),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: PgTokens.space5, vertical: 13),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: PgTokens.colorBorder)),
        ),
        child: Row(
          children: [
            _RowIcon(badge: badge),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    booking.address ?? 'งานรักษาความปลอดภัย',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: PgTokens.colorTextStrong,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    statusLine,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11.5, color: PgTokens.colorTextMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: PgTokens.space2),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _StatusBadge(badge: badge),
                const SizedBox(height: 3),
                if (total > 0)
                  Text(
                    Money.format(total),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'IBMPlexMono',
                      fontFeatures: const [FontFeature.tabularFigures()],
                      // Design: cancelled amounts render muted.
                      color: cancelled
                          ? PgTokens.colorTextMuted
                          : PgTokens.colorTextStrong,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 40×40 radius-11 icon badge: amber shield (active) / green check (done) / red X (cancelled).
class _RowIcon extends StatelessWidget {
  const _RowIcon({required this.badge});

  final HistoryBadge badge;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, icon) = switch (badge) {
      HistoryBadge.active => (
          PgTokens.colorWarningBg,
          PgTokens.colorAmber600,
          Icons.shield_outlined
        ),
      HistoryBadge.done => (
          PgTokens.colorGreen100,
          PgTokens.colorGreen700,
          Icons.check
        ),
      HistoryBadge.cancelled => (
          PgTokens.colorDangerBg,
          PgTokens.colorDanger,
          Icons.close
        ),
    };
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(PgTokens.radiusLg),
      ),
      child: Icon(icon, size: 18, color: fg),
    );
  }
}

/// The 10px w600 status word pill (the design badges are the literal lowercase words).
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.badge});

  final HistoryBadge badge;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (badge) {
      HistoryBadge.active => (PgTokens.colorWarningBg, PgTokens.colorAmber600),
      HistoryBadge.done => (PgTokens.colorGreen100, PgTokens.colorGreen700),
      HistoryBadge.cancelled => (PgTokens.colorDangerBg, PgTokens.colorDanger),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(PgTokens.radiusFull),
      ),
      child: Text(
        badge.label,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }
}

/// No bookings at all (the spec has no designed empty state — house empty pattern).
class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory({required this.isThai});

  final bool isThai;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 100),
        const Icon(Icons.event_note_outlined,
            size: 48, color: PgTokens.colorTextFaint),
        const SizedBox(height: PgTokens.space3),
        Text(
          isThai ? 'ยังไม่มีการจอง' : 'No bookings yet',
          textAlign: TextAlign.center,
          style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: PgTokens.colorText),
        ),
        const SizedBox(height: PgTokens.space2),
        Text(
          isThai
              ? 'เรียก รปภ. ครั้งแรกได้จากหน้าหลัก'
              : 'Book your first guard from Home',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: PgTokens.colorTextMuted),
        ),
      ],
    );
  }
}
