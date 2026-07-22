import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../core/controllers/active_job_controller.dart';
import '../../core/controllers/guard_jobs_controller.dart';
import '../../core/controllers/locale_controller.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/pguard_header.dart';
import '../../widgets/primary_button.dart';
import '../booking/widgets/reason_tile.dart';

/// Guard back-out flow (Mobile - Cancellation.html STATE 3): escalation warning →
/// reason + admin notes → `PUT /v1/bookings/{id}/decline` via the existing
/// [ActiveJobController.withdraw]. The reason and notes are DISPLAY-ONLY — the decline
/// endpoint takes no body (no such API fields exist); the design frames this as a
/// request that admin reviews. Replaces the old AlertDialog on the active-job screen.
class WithdrawScreen extends ConsumerStatefulWidget {
  const WithdrawScreen({super.key, required this.bookingId});

  final String bookingId;

  @override
  ConsumerState<WithdrawScreen> createState() => _WithdrawScreenState();
}

class _WithdrawScreenState extends ConsumerState<WithdrawScreen> {
  /// Design STATE 3 reason options — "เหตุฉุกเฉินส่วนตัว" pre-selected. Rendered in the
  /// active locale; the reason is DISPLAY-ONLY (decline takes no body), so single-language
  /// text is fine.
  static List<String> _reasonsFor(bool isThai) => isThai
      ? const [
          'เหตุฉุกเฉินส่วนตัว',
          'ป่วย',
          'เดินทางไปไม่ได้',
        ]
      : const [
          'Personal emergency',
          'Sick',
          "Can't reach site",
        ];

  int _selected = 0;
  final TextEditingController _notes = TextEditingController();

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  /// Design subtitle shows a short job code ("BK-48280"); v2 ids are UUIDs, so we show
  /// `BK-` + the first 5 hex chars (same shortening as the cancellation screen).
  String get _shortId {
    final compact = widget.bookingId.replaceAll('-', '');
    final tail = compact.length >= 5 ? compact.substring(0, 5) : compact;
    return 'BK-${tail.toUpperCase()}';
  }

  Future<void> _submit() async {
    final isThai = ref.read(localeControllerProvider) == AppLocale.th;
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
    final ok = await ref
        .read(activeJobControllerProvider(widget.bookingId).notifier)
        .withdraw();
    if (!mounted) return;
    if (ok) {
      messenger.showSnackBar(SnackBar(
          content:
              Text(isThai ? 'ส่งคำขอถอนงานแล้ว' : 'Withdrawal submitted')));
      // Drop the cached jobs list so the withdrawn job stops showing as active on the dashboard
      // (mirrors _backToJobs; without this the guard lands on a stale 'งานที่กำลังทำ' — deep-review).
      ref.invalidate(guardJobsControllerProvider);
      context.go('/home/guard');
    } else {
      final error = ref
          .read(activeJobControllerProvider(widget.bookingId))
          .valueOrNull
          ?.error;
      messenger.showSnackBar(SnackBar(
          content: Text(
              error ?? (isThai ? 'เกิดข้อผิดพลาด' : 'Something went wrong'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    // Shared with the active-job screen below in the stack (busy flag + address).
    final jobState =
        ref.watch(activeJobControllerProvider(widget.bookingId)).valueOrNull;
    final address = jobState?.booking.address;
    final busy = jobState?.busy ?? false;
    // Design: notes are optional — a reason is always selected (defaults to index 0), so Submit
    // is enabled whenever we're not mid-request.
    final canSubmit = !busy;
    final reasons = _reasonsFor(isThai);

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
                    padding: const EdgeInsets.fromLTRB(24, 6, 24, 14),
                    child: TextField(
                      controller: _notes,
                      minLines: 2,
                      maxLines: 4,
                      style: const TextStyle(
                          fontSize: 14, color: PgTokens.colorText),
                      decoration: InputDecoration(
                        hintText: isThai
                            ? 'อธิบายเพิ่มเติมสำหรับแอดมิน…'
                            : 'Add details for admin…',
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
                          borderSide: const BorderSide(
                              color: PgTokens.colorBorderStrong, width: 1.5),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                              color: PgTokens.colorPrimary, width: 1.5),
                        ),
                      ),
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
