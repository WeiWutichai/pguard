import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../core/controllers/booking_status_controller.dart';
import '../../core/controllers/locale_controller.dart';
import '../../core/models/booking.dart';
import '../../core/models/money.dart';
import '../../widgets/pguard_header.dart';
import '../../widgets/primary_button.dart';
import 'widgets/reason_tile.dart';

/// What the live-status screen already knows about the booking, passed via `extra` on
/// `/booking/:id/cancel` so the header/banner render instantly. The screen also watches
/// the booking-status controller (shared with live status) as a fallback for deep links.
class CancellationArgs {
  const CancellationArgs({this.address, this.totalSatang});

  final String? address;

  /// Display total in satang (`base_fee × hours × guard_count + tip`) — drives the
  /// dynamic refund amount in the info banner; `null` → the amount is omitted.
  final int? totalSatang;
}

/// Customer cancellation flow (Mobile - Cancellation.html STATE 1 + STATE 2): pick a
/// reason → confirm via the bottom sheet → `PUT /v1/bookings/{id}/cancel` (pre-arrival
/// only, per the contract). The reason is DISPLAY-ONLY — the cancel endpoint takes no
/// body. On success we pop back to live status, whose state is already updated (and the
/// WS `cancelled` frame follows).
class CancellationScreen extends ConsumerStatefulWidget {
  const CancellationScreen({super.key, required this.bookingId, this.args});

  final String bookingId;
  final CancellationArgs? args;

  @override
  ConsumerState<CancellationScreen> createState() => _CancellationScreenState();
}

class _CancellationScreenState extends ConsumerState<CancellationScreen> {
  /// Design STATE 1 reason options — "เปลี่ยนแผน" pre-selected. Rendered in the
  /// active locale (the chosen reason is DISPLAY-ONLY — never sent — so the
  /// single-language text is fine for the cancel call too).
  static List<String> _reasonsFor(bool isThai) => isThai
      ? const [
          'เปลี่ยนแผน',
          'แจ้งผิดพลาด',
          'ไม่ต้องการแล้ว',
          'อื่นๆ',
        ]
      : const [
          'Changed plans',
          'Booked by mistake',
          'No longer needed',
          'Other',
        ];

  int _selected = 0;
  bool _busy = false;

  /// Design subtitle shows a short booking code ("BK-48291"); v2 ids are UUIDs, so we
  /// show `BK-` + the first 5 hex chars (house pattern: AvailableGuard.shortId).
  String get _shortId {
    final compact = widget.bookingId.replaceAll('-', '');
    final tail = compact.length >= 5 ? compact.substring(0, 5) : compact;
    return 'BK-${tail.toUpperCase()}';
  }

  /// The refundable display total: prefer what live status passed via `extra`, else
  /// derive from the watched booking (same satang math as the home/payment screens).
  /// `null` → unknown → the banner omits the amount.
  int? _totalSatang(Booking? booking) {
    final fromArgs = widget.args?.totalSatang;
    if (fromArgs != null) return fromArgs;
    final b = booking;
    if (b == null || b.baseFee == null) return null;
    final baseFeeSatang = Money.satangFromString(b.baseFee);
    final hours = b.hours ?? 0;
    if (baseFeeSatang <= 0 || hours <= 0) return null;
    return Money.total(
      baseFeeSatang: baseFeeSatang,
      hours: hours,
      guardCount: b.guardCount ?? 1,
      tipSatang: Money.satangFromString(b.tip),
    );
  }

  Future<void> _confirmAndCancel(int? totalSatang) async {
    final isThai = ref.read(localeControllerProvider) == AppLocale.th;
    final isPaid = ref
            .read(bookingStatusControllerProvider(widget.bookingId))
            .valueOrNull
            ?.isPaid ??
        false;
    final yes = await _showConfirmSheet(totalSatang, isThai, isPaid);
    if (yes != true || !mounted) return;

    setState(() => _busy = true);
    // The contract endpoint takes NO body — the reason rides along display-only.
    final error = await ref
        .read(bookingStatusControllerProvider(widget.bookingId).notifier)
        .cancel(reason: _reasonsFor(isThai)[_selected]);
    if (!mounted) return;
    setState(() => _busy = false);

    final messenger = ScaffoldMessenger.of(context);
    if (error != null) {
      messenger.showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    messenger.showSnackBar(SnackBar(
        content: Text(isThai ? 'ยกเลิกการจองแล้ว' : 'Booking cancelled')));
    // Back to live status — its state is already the cancelled booking (+ WS follows).
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/home/customer');
    }
  }

  /// STATE 2 confirm sheet: grab handle, 60px danger-tinted warning circle, 19/600
  /// title, 13.5 muted body, stacked danger + sunken CTAs.
  Future<bool?> _showConfirmSheet(int? totalSatang, bool isThai, bool isPaid) {
    final String body;
    if (!isPaid) {
      // Nothing was charged → don't promise a refund.
      body = isThai
          ? 'ยังไม่มีการเรียกเก็บเงิน — ยกเลิกได้ฟรี และจะแจ้งเจ้าหน้าที่ การกระทำนี้ย้อนกลับไม่ได้'
          : "You haven't been charged — cancelling is free. We'll notify the guard. This can't be undone.";
    } else if (totalSatang != null) {
      body = isThai
          ? 'ระบบจะคืนเงิน ${Money.format(totalSatang)} และแจ้งเจ้าหน้าที่ การกระทำนี้ย้อนกลับไม่ได้'
          : "We'll refund ${Money.format(totalSatang)} and notify the guard. This can't be undone.";
    } else {
      body = isThai
          ? 'ระบบจะคืนเงินและแจ้งเจ้าหน้าที่ การกระทำนี้ย้อนกลับไม่ได้'
          : "We'll refund you and notify the guard. This can't be undone.";
    }
    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: PgTokens.colorSurface,
      // Natural content height (the default sheet caps shorter than this content on
      // small viewports); the scroll view below is the small-screen fallback.
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        // Design 24px top corners → radius2xl, the nearest token.
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(PgTokens.radius2xl)),
      ),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Grab handle: 42×5, border-strong, radius 3.
              Container(
                width: 42,
                height: 5,
                margin: const EdgeInsets.only(top: 6, bottom: 14),
                decoration: BoxDecoration(
                  color: PgTokens.colorBorderStrong,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 8, horizontal: 28),
                child: Column(
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: const BoxDecoration(
                        color: PgTokens.colorDangerBg,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.warning_amber_rounded,
                          size: 26, color: PgTokens.colorDanger),
                    ),
                    Text(
                      isThai ? 'ยกเลิกงานนี้?' : 'Cancel this job?',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w600,
                        color: PgTokens.colorText,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      body,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13.5,
                        height: 1.55,
                        color: PgTokens.colorTextMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
                child: Column(
                  children: [
                    PgPrimaryButton(
                      label: isThai ? 'ใช่ ยกเลิกงาน' : 'Yes, cancel',
                      color: PgTokens.colorDanger,
                      onPressed: () => Navigator.pop(sheetContext, true),
                    ),
                    const SizedBox(height: 10),
                    // Sunken dismiss CTA (design `.cta-ghost`: bg-sunken + text-strong).
                    PgPrimaryButton(
                      label: isThai ? 'เก็บงานไว้' : 'Keep booking',
                      color: PgTokens.colorSunken,
                      foreground: PgTokens.colorText,
                      onPressed: () => Navigator.pop(sheetContext, false),
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

  @override
  Widget build(BuildContext context) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    // Shared with the live-status screen below in the stack; on a cold deep link this
    // spins up the snapshot + WS feed itself.
    final booking = ref
        .watch(bookingStatusControllerProvider(widget.bookingId))
        .valueOrNull;
    final address = widget.args?.address ?? booking?.address;
    final totalSatang = _totalSatang(booking);
    final isPaid = booking?.isPaid ?? false;
    final reasons = _reasonsFor(isThai);

    return Scaffold(
      backgroundColor: PgTokens.colorBg,
      appBar: PGuardHeader(
        light: true,
        title: isThai ? 'ยกเลิกการจอง' : 'Cancellation',
        subtitle: address != null ? '$_shortId · $address' : _shortId,
        showBack: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 6, 24, 14),
                    child: Text(
                      isThai
                          ? 'เลือกเหตุผลในการยกเลิก'
                          : 'Why are you cancelling?',
                      style: const TextStyle(
                          fontSize: 14, color: PgTokens.colorTextMuted),
                    ),
                  ),
                  for (var i = 0; i < reasons.length; i++)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
                      child: PgReasonTile(
                        label: reasons[i],
                        selected: _selected == i,
                        onTap: () => setState(() => _selected = i),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
                    child: _RefundNote(
                        totalSatang: totalSatang,
                        isPaid: isPaid,
                        isThai: isThai),
                  ),
                ],
              ),
            ),
            Padding(
              // Design footer: 16px 20px (+ the SafeArea handles the inset).
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: PgPrimaryButton(
                label: isThai ? 'ยืนยันยกเลิกงาน' : 'Confirm cancellation',
                color: PgTokens.colorDanger,
                busy: _busy,
                onPressed: _busy ? null : () => _confirmAndCancel(totalSatang),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Design `.refund-note`: clock icon + 13px info-blue copy on the `--info-bg` wash.
class _RefundNote extends StatelessWidget {
  const _RefundNote(
      {this.totalSatang, required this.isPaid, required this.isThai});

  final int? totalSatang;
  final bool isPaid;
  final bool isThai;

  @override
  Widget build(BuildContext context) {
    final amount = totalSatang != null ? ' ${Money.format(totalSatang!)}' : '';
    // Only promise a refund when money was actually taken — an unpaid cancel (requested / accepted-
    // before-pay) charges nothing, so "we'll refund ฿X in 3–5 days" was a lie (deep-review).
    final copy = !isPaid
        ? (isThai
            ? 'ยังไม่มีการเรียกเก็บเงิน — ยกเลิกได้ฟรี'
            : "You haven't been charged — cancelling is free")
        : (isThai
            ? 'ยกเลิกก่อนเริ่มงาน — คืนเงินเต็มจำนวน$amount ภายใน 3–5 วันทำการ'
            : 'Cancelled before start — full$amount refund in 3–5 business days');
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      decoration: BoxDecoration(
        color: PgTokens.colorInfoBg,
        borderRadius: BorderRadius.circular(PgTokens.radiusXl),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.schedule, size: 18, color: PgTokens.colorInfo),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              copy,
              style: const TextStyle(
                fontSize: 13,
                height: 1.5,
                color: PgTokens.colorInfo,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
