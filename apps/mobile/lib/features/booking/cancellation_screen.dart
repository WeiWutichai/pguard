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
import 'widgets/cancel_reason.dart';
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
/// reason (+ an optional note) → confirm via the bottom sheet →
/// `PUT /v1/bookings/{id}/cancel { reason, note? }` (pre-arrival only, per the contract).
///
/// The picked reason is SENT as a stable code (`PgCancelReason.customer`) — it is persisted on
/// the booking and rides `pguard.events.booking.cancelled`, so the guard, the notification and
/// admin all see WHY. The note is required when the reason is `other` (the server backstops with
/// 400 `CANCEL_NOTE_REQUIRED`; we block locally first so the user isn't bounced by a round-trip).
///
/// On success we pop back to live status, whose state is already updated (and the WS `cancelled`
/// frame follows).
class CancellationScreen extends ConsumerStatefulWidget {
  const CancellationScreen({super.key, required this.bookingId, this.args});

  final String bookingId;
  final CancellationArgs? args;

  @override
  ConsumerState<CancellationScreen> createState() => _CancellationScreenState();
}

class _CancellationScreenState extends ConsumerState<CancellationScreen> {
  /// The selected reason CODE — what actually goes on the wire. Defaults to the design's
  /// pre-selected first option (`changed_plan`); the LABEL is looked up per-locale via
  /// [PgCancelReason.labelFor], so the code and the copy can never drift.
  String _reason = PgCancelReason.customer.first;

  /// Free-text detail (optional in general, REQUIRED when the reason is `other`).
  final TextEditingController _note = TextEditingController();

  /// Set when the user submits `other` with a blank note — drives the inline message under the
  /// field. Cleared as soon as they type or switch reason (no nagging).
  bool _noteMissing = false;

  bool _busy = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  /// Whether the current selection obliges a note (only `other` does).
  bool get _noteRequired => PgCancelReason.requiresNote(_reason);

  /// Design subtitle shows a short booking code ("BK-48291"); v2 ids are UUIDs, so we
  /// show `BK-` + the first 5 hex chars (house pattern: AvailableGuard.shortId).
  String get _shortId {
    final compact = widget.bookingId.replaceAll('-', '');
    final tail = compact.length >= 5 ? compact.substring(0, 5) : compact;
    return 'BK-${tail.toUpperCase()}';
  }

  /// What was PAID, in satang (VAT included — it is what actually left the customer's account):
  /// prefer what live status passed via `extra`, else derive from the watched booking.
  /// `null` → unknown → the copy omits the amount rather than guessing.
  int? _totalSatang(Booking? booking) {
    final fromArgs = widget.args?.totalSatang;
    if (fromArgs != null) return fromArgs;
    return booking?.displayTotalSatang;
  }

  /// The cancellation fee this booking was sold under, clamped to what was actually paid.
  ///
  /// "Take what is there, never leave a debt" — the server applies the same `min()`, so a ฿1 job
  /// with a ฿100 fee keeps ฿1 and refunds ฿0 rather than billing ฿99. Nothing paid → no fee.
  int _feeSatang(Booking? booking, int? paidSatang, bool isPaid) {
    if (!isPaid || paidSatang == null) return 0;
    final fee = booking?.cancellationFeeSatang ?? 0;
    return fee < paidSatang ? fee : paidSatang;
  }

  /// The live booking, or null while it loads — the confirm copy needs its cancellation fee.
  Booking? get _currentBooking =>
      ref.read(bookingStatusControllerProvider(widget.bookingId)).valueOrNull;

  Future<void> _confirmAndCancel(int? totalSatang) async {
    final isThai = ref.read(localeControllerProvider) == AppLocale.th;
    final note = PgCancelReason.normalizeNote(_note.text);
    // Gate BEFORE the confirm sheet: a user who taps through the scary "Yes, cancel" only to be
    // rejected by the server's CANCEL_NOTE_REQUIRED would have to redo the whole flow.
    if (_noteRequired && note == null) {
      setState(() => _noteMissing = true);
      return;
    }
    final isPaid = ref
            .read(bookingStatusControllerProvider(widget.bookingId))
            .valueOrNull
            ?.isPaid ??
        false;
    final yes = await _showConfirmSheet(totalSatang, isThai, isPaid);
    if (yes != true || !mounted) return;

    setState(() => _busy = true);
    // The CODE goes on the wire (never the localized label) + the trimmed note when present.
    final error = await ref
        .read(bookingStatusControllerProvider(widget.bookingId).notifier)
        .cancel(reason: _reason, note: note);
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
      final fee = _feeSatang(_currentBooking, totalSatang, isPaid);
      final refund = totalSatang - fee;
      body = fee > 0
          ? (isThai
              ? 'ยกเลิกก่อนเริ่มงานมีค่าธรรมเนียม ${Money.format(fee)} — ระบบจะคืนเงิน '
                  '${Money.format(refund)} และแจ้งเจ้าหน้าที่ การกระทำนี้ย้อนกลับไม่ได้'
              : 'Cancelling costs a ${Money.format(fee)} fee — we\'ll refund '
                  "${Money.format(refund)} and notify the guard. This can't be undone.")
          : (isThai
              ? 'ระบบจะคืนเงิน ${Money.format(refund)} และแจ้งเจ้าหน้าที่ การกระทำนี้ย้อนกลับไม่ได้'
              : "We'll refund ${Money.format(refund)} and notify the guard. This can't be undone.");
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
                  for (final code in PgCancelReason.customer)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
                      child: PgReasonTile(
                        label: PgCancelReason.labelFor(code, isThai),
                        selected: _reason == code,
                        onTap: () => setState(() {
                          _reason = code;
                          // Switching away from (or back to) `other` clears a stale complaint.
                          _noteMissing = false;
                        }),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
                    child: _NoteField(
                      controller: _note,
                      isThai: isThai,
                      noteRequired: _noteRequired,
                      showMissing: _noteMissing,
                      onChanged: () {
                        if (_noteMissing) setState(() => _noteMissing = false);
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
                    child: _RefundNote(
                        totalSatang: totalSatang,
                        feeSatang: _feeSatang(booking, totalSatang, isPaid),
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

/// The free-text detail that rides along with the reason code (`note` on the cancel body).
/// Styled on the review-screen comment precedent: a [PgTokens.colorSunken] card holding a
/// borderless 2–5 line field capped at [PgCancelReason.maxNoteLength] with the counter hidden.
/// Shown for EVERY reason (a note is always useful to the guard/admin) but only ENFORCED for
/// `other`, where [showMissing] surfaces the inline danger message.
class _NoteField extends StatelessWidget {
  const _NoteField({
    required this.controller,
    required this.isThai,
    required this.noteRequired,
    required this.showMissing,
    required this.onChanged,
  });

  final TextEditingController controller;
  final bool isThai;
  final bool noteRequired;
  final bool showMissing;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          PgCancelReason.noteLabel(isThai, required: noteRequired),
          style: const TextStyle(fontSize: 14, color: PgTokens.colorTextMuted),
        ),
        const SizedBox(height: PgTokens.space2),
        Container(
          decoration: BoxDecoration(
            color: PgTokens.colorSunken,
            borderRadius: BorderRadius.circular(PgTokens.radiusXl),
            // A missing required note is called out on the container itself, not just in words.
            border: showMissing
                ? Border.all(color: PgTokens.colorDanger, width: 1.5)
                : null,
          ),
          padding: const EdgeInsets.symmetric(
              horizontal: PgTokens.space4, vertical: 4),
          child: TextField(
            controller: controller,
            minLines: 2,
            maxLines: 5,
            maxLength: PgCancelReason.maxNoteLength,
            onChanged: (_) => onChanged(),
            style: const TextStyle(fontSize: 14, color: PgTokens.colorText),
            decoration: InputDecoration(
              border: InputBorder.none,
              counterText: '',
              hintText: PgCancelReason.noteHint(isThai, required: noteRequired),
              hintStyle:
                  const TextStyle(fontSize: 14, color: PgTokens.colorTextFaint),
            ),
          ),
        ),
        if (showMissing) ...[
          const SizedBox(height: PgTokens.space2),
          Text(
            PgCancelReason.noteMissingMessage(isThai),
            style: const TextStyle(fontSize: 13, color: PgTokens.colorDanger),
          ),
        ],
      ],
    );
  }
}

/// Design `.refund-note`: clock icon + 13px info-blue copy on the `--info-bg` wash.
class _RefundNote extends StatelessWidget {
  const _RefundNote(
      {this.totalSatang,
      required this.feeSatang,
      required this.isPaid,
      required this.isThai});

  /// What was PAID (VAT included), not what will be refunded — the refund is this minus the fee.
  final int? totalSatang;

  /// The cancellation fee, already clamped to what was paid (0 when unpaid or no fee).
  final int feeSatang;
  final bool isPaid;
  final bool isThai;

  @override
  Widget build(BuildContext context) {
    // The figure quoted is the REFUND — what comes back — not what was paid.
    final refund = totalSatang == null ? null : totalSatang! - feeSatang;
    final amount = refund != null ? ' ${Money.format(refund)}' : '';
    // Only promise a refund when money was actually taken — an unpaid cancel (requested / accepted-
    // before-pay) charges nothing, so "we'll refund ฿X in 3–5 days" was a lie (deep-review).
    final feeText = feeSatang > 0 ? ' ${Money.format(feeSatang)}' : '';
    final copy = !isPaid
        ? (isThai
            ? 'ยังไม่มีการเรียกเก็บเงิน — ยกเลิกได้ฟรี'
            : "You haven't been charged — cancelling is free")
        : feeSatang > 0
            // Say the fee out loud here, not only in the confirm sheet: the amount changes what a
            // reasonable person decides, so it belongs where they are still deciding.
            ? (isThai
                ? 'ยกเลิกก่อนเริ่มงาน — มีค่าธรรมเนียม$feeText คืนเงิน$amount ภายใน 3–5 วันทำการ'
                : 'Cancelled before start —$feeText fee,$amount refunded in 3–5 business days')
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
