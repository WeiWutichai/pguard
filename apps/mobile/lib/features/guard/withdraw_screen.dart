import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../core/controllers/active_job_controller.dart';
import '../../core/controllers/booking_status_controller.dart';
import '../../core/controllers/guard_jobs_controller.dart';
import '../../core/controllers/locale_controller.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/pguard_header.dart';
import '../../widgets/primary_button.dart';
import '../booking/widgets/cancel_reason.dart';
import '../booking/widgets/reason_tile.dart';

/// Guard back-out flow (Mobile - Cancellation.html STATE 3): escalation warning →
/// reason + admin notes → `PUT /v1/bookings/{id}/decline { reason, note? }`.
///
/// The picked reason is SENT as a stable code (`PgCancelReason.guard`) and the notes ride along as
/// `note` — that is the whole point of the screen: admin reviews the withdrawal, and the customer's
/// cancellation notice says WHY. `other` requires the note (server backstop: 400
/// `CANCEL_NOTE_REQUIRED`), so we block locally first.
///
/// The call goes through [BookingStatusController.decline], which shares the cancel/decline body
/// shape with the customer flow; the active-job screen below observes the resulting `declined`
/// terminal over the booking-status feed it already listens to. Replaces the old AlertDialog on
/// the active-job screen.
class WithdrawScreen extends ConsumerStatefulWidget {
  const WithdrawScreen({super.key, required this.bookingId});

  final String bookingId;

  @override
  ConsumerState<WithdrawScreen> createState() => _WithdrawScreenState();
}

class _WithdrawScreenState extends ConsumerState<WithdrawScreen> {
  /// The selected reason CODE — what goes on the wire. Defaults to the design's pre-selected
  /// first option (`emergency`); the LABEL comes from [PgCancelReason.labelFor] per locale, so
  /// code and copy can never drift.
  String _reason = PgCancelReason.guard.first;

  /// The admin note (optional in general, REQUIRED when the reason is `other`).
  final TextEditingController _notes = TextEditingController();

  /// Set when the guard submits `other` with a blank note; cleared on typing / reason change.
  bool _noteMissing = false;

  /// In-flight flag for the decline PUT (the active-job controller's own `busy` no longer covers
  /// this call — the body-carrying decline lives on the booking-status controller).
  bool _busy = false;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  /// Whether the current selection obliges a note (only `other` does).
  bool get _noteRequired => PgCancelReason.requiresNote(_reason);

  /// Design subtitle shows a short job code ("BK-48280"); v2 ids are UUIDs, so we show
  /// `BK-` + the first 5 hex chars (same shortening as the cancellation screen).
  String get _shortId {
    final compact = widget.bookingId.replaceAll('-', '');
    final tail = compact.length >= 5 ? compact.substring(0, 5) : compact;
    return 'BK-${tail.toUpperCase()}';
  }

  Future<void> _submit() async {
    final isThai = ref.read(localeControllerProvider) == AppLocale.th;
    final note = PgCancelReason.normalizeNote(_notes.text);
    // Gate BEFORE the confirm dialog: bouncing the guard on the server's CANCEL_NOTE_REQUIRED
    // after they already confirmed a scary destructive action means redoing the whole flow.
    if (_noteRequired && note == null) {
      setState(() => _noteMissing = true);
      return;
    }
    // Confirm before the REAL server decline (PUT /decline) — unlike skipping an open offer, this
    // gives up a job the guard accepted, so the backend notifies the customer.
    final yes = await showConfirmDialog(
      context,
      isThai: isThai,
      title: isThai ? 'ยืนยันถอนตัวจากงานนี้?' : 'Withdraw from this job?',
      message: isThai
          ? 'ลูกค้าจะได้รับแจ้ง และเรื่องนี้จะถูกส่งให้แอดมินตรวจสอบ'
          : "The customer will be notified, and this is escalated to admin.",
      confirmLabel: isThai ? 'ถอนตัว' : 'Withdraw',
      destructive: true,
    );
    if (!yes || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    // The CODE + trimmed note go on the wire. The active-job screen below in the stack listens to
    // this same booking-status controller, so the resulting `declined` terminal folds into its
    // state without a second round-trip.
    final error = await ref
        .read(bookingStatusControllerProvider(widget.bookingId).notifier)
        .decline(reason: _reason, note: note);
    if (!mounted) return;
    setState(() => _busy = false);
    if (error != null) {
      messenger.showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    messenger.showSnackBar(SnackBar(
        content: Text(isThai ? 'ส่งคำขอถอนงานแล้ว' : 'Withdrawal submitted')));
    // Drop the cached jobs list so the withdrawn job stops showing as active on the dashboard
    // (mirrors _backToJobs; without this the guard lands on a stale 'งานที่กำลังทำ' — deep-review).
    ref.invalidate(guardJobsControllerProvider);
    context.go('/home/guard');
  }

  @override
  Widget build(BuildContext context) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    // Shared with the active-job screen below in the stack (busy flag + address).
    final jobState =
        ref.watch(activeJobControllerProvider(widget.bookingId)).valueOrNull;
    final address = jobState?.booking.address;
    // Busy = our own decline PUT, or an active-job transition already running underneath.
    final busy = _busy || (jobState?.busy ?? false);
    // Design: a reason is always selected (defaults to index 0), so Submit stays ENABLED whenever
    // we're not mid-request — the `other`-needs-a-note rule is enforced as an inline message on
    // tap, not by greying the button out (a dead button with no explanation reads as a bug).
    final canSubmit = !busy;

    return Scaffold(
      backgroundColor: PgTokens.colorBg,
      appBar: PGuardHeader(
        title: isThai ? 'ขอถอนจากงาน' : 'Withdraw from job',
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
                    padding: const EdgeInsets.fromLTRB(24, 6, 24, 0),
                    child: _EscalationBanner(isThai: isThai),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 14, 24, 8),
                    child: Text(
                      isThai ? 'เหตุผล' : 'Reason',
                      style: const TextStyle(
                          fontSize: 14, color: PgTokens.colorTextMuted),
                    ),
                  ),
                  for (final code in PgCancelReason.guard)
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
                    padding: const EdgeInsets.fromLTRB(24, 6, 24, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _notes,
                          minLines: 2,
                          maxLines: 5,
                          // Server cap (counted in characters — Thai is multi-byte).
                          maxLength: PgCancelReason.maxNoteLength,
                          onChanged: (_) {
                            if (_noteMissing) {
                              setState(() => _noteMissing = false);
                            }
                          },
                          style: const TextStyle(
                              fontSize: 14, color: PgTokens.colorText),
                          decoration: InputDecoration(
                            counterText: '',
                            hintText: _noteRequired
                                ? PgCancelReason.noteHint(isThai,
                                    required: true)
                                : (isThai
                                    ? 'อธิบายเพิ่มเติมสำหรับแอดมิน…'
                                    : 'Add details for admin…'),
                            hintStyle: const TextStyle(
                                fontSize: 14, color: PgTokens.colorTextFaint),
                            filled: true,
                            fillColor: PgTokens.colorSurface,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                                vertical: 12, horizontal: 14),
                            enabledBorder: OutlineInputBorder(
                              // Design notes textarea: 12px corners.
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                  color: _noteMissing
                                      ? PgTokens.colorDanger
                                      : PgTokens.colorBorderStrong,
                                  width: 1.5),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                  color: _noteMissing
                                      ? PgTokens.colorDanger
                                      : PgTokens.colorPrimary,
                                  width: 1.5),
                            ),
                          ),
                        ),
                        if (_noteMissing) ...[
                          const SizedBox(height: PgTokens.space2),
                          Text(
                            PgCancelReason.noteMissingMessage(isThai),
                            style: const TextStyle(
                                fontSize: 13, color: PgTokens.colorDanger),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: PgPrimaryButton(
                label: isThai ? 'ส่งคำขอถอนงาน' : 'Submit request',
                color: PgTokens.colorDanger,
                busy: busy,
                onPressed: canSubmit ? _submit : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Design `.refund-note.warn`: warning triangle + 13px amber-700 copy on the warning wash.
class _EscalationBanner extends StatelessWidget {
  const _EscalationBanner({required this.isThai});

  final bool isThai;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      decoration: BoxDecoration(
        color: PgTokens.colorWarningBg,
        borderRadius: BorderRadius.circular(PgTokens.radiusXl),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.warning_amber_rounded,
                size: 18, color: PgTokens.colorAmber700),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              isThai
                  ? 'การถอนงานเป็นกรณีพิเศษ จะถูกส่งให้แอดมินตรวจสอบ '
                      'และอาจมีผลต่อคะแนนของคุณ'
                  : "Backing out is rare — it's escalated to admin and "
                      'may affect your rating.',
              style: const TextStyle(
                fontSize: 13,
                height: 1.5,
                color: PgTokens.colorAmber700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
