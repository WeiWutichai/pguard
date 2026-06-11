import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../core/controllers/active_job_controller.dart';
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
  /// Design STATE 3 reason options — "เหตุฉุกเฉินส่วนตัว" pre-selected.
  static const List<String> _reasons = [
    'เหตุฉุกเฉินส่วนตัว / Personal emergency',
    'ป่วย / Sick',
    "เดินทางไปไม่ได้ / Can't reach site",
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
    final messenger = ScaffoldMessenger.of(context);
    final ok = await ref
        .read(activeJobControllerProvider(widget.bookingId).notifier)
        .withdraw();
    if (!mounted) return;
    if (ok) {
      messenger.showSnackBar(const SnackBar(
          content: Text('ส่งคำขอถอนงานแล้ว / Withdrawal submitted')));
      context.go('/home/guard');
    } else {
      final error = ref
          .read(activeJobControllerProvider(widget.bookingId))
          .valueOrNull
          ?.error;
      messenger.showSnackBar(SnackBar(
          content:
              Text(error ?? 'เกิดข้อผิดพลาด / Something went wrong')));
    }
  }

  @override
  Widget build(BuildContext context) {
    // Shared with the active-job screen below in the stack (busy flag + address).
    final jobState =
        ref.watch(activeJobControllerProvider(widget.bookingId)).valueOrNull;
    final address = jobState?.booking.address;
    final busy = jobState?.busy ?? false;
    // Design interaction note: the notes textarea is required before submit enables.
    final canSubmit = !busy && _notes.text.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: PgTokens.colorBg,
      appBar: PGuardHeader(
        title: 'ขอถอนจากงาน',
        subtitle: address != null ? '$_shortId · $address' : _shortId,
        showBack: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(24, 6, 24, 0),
                    child: _EscalationBanner(),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(24, 14, 24, 8),
                    child: Text(
                      'เหตุผล',
                      style: TextStyle(
                          fontSize: 14, color: PgTokens.colorTextMuted),
                    ),
                  ),
                  for (var i = 0; i < _reasons.length; i++)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
                      child: PgReasonTile(
                        label: _reasons[i],
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
                      onChanged: (_) => setState(() {}),
                      style: const TextStyle(
                          fontSize: 14, color: PgTokens.colorText),
                      decoration: InputDecoration(
                        hintText: 'อธิบายเพิ่มเติมสำหรับแอดมิน…',
                        hintStyle: const TextStyle(
                            fontSize: 14, color: PgTokens.colorTextFaint),
                        filled: true,
                        fillColor: PgTokens.colorSurface,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            vertical: 12, horizontal: 14),
                        enabledBorder: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(PgTokens.radiusLg),
                          borderSide: const BorderSide(
                              color: PgTokens.colorBorderStrong, width: 1.5),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(PgTokens.radiusLg),
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
                label: 'ส่งคำขอถอนงาน / Submit request',
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
  const _EscalationBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      decoration: BoxDecoration(
        color: PgTokens.colorWarningBg,
        borderRadius: BorderRadius.circular(PgTokens.radiusXl),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.warning_amber_rounded,
                size: 18, color: PgTokens.colorAmber700),
          ),
          SizedBox(width: 11),
          Expanded(
            child: Text(
              'การถอนงานเป็นกรณีพิเศษ จะถูกส่งให้แอดมินตรวจสอบ และอาจมีผลต่อคะแนนของคุณ / '
              "Backing out is rare — it's escalated to admin and may affect your rating.",
              style: TextStyle(
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
