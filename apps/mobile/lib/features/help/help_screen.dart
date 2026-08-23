import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../core/controllers/locale_controller.dart';
import '../../core/controllers/support_ticket_controller.dart';
import '../../widgets/pguard_header.dart';
import '../../widgets/primary_button.dart';

/// System screen 9 — Help, reduced (H1) to a single purpose: **file a support ticket**
/// ("แจ้งปัญหา / ส่งความคิดเห็น"). The old static FAQ + informational contact rows are gone —
/// the page is now a real form that POSTs `/support/tickets` (a persisted ticket an admin reads),
/// replacing the dead contact rows that faked an action. A kind toggle (problem / feedback) + a
/// message field + submit, with inline success + error states.
class HelpScreen extends ConsumerStatefulWidget {
  const HelpScreen({super.key});

  @override
  ConsumerState<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends ConsumerState<HelpScreen> {
  SupportTicketKind _kind = SupportTicketKind.problem;
  final TextEditingController _message = TextEditingController();
  // Flips to true after a successful submit → the form is replaced by a thank-you panel (so the
  // ticket can't be double-filed and the user gets clear confirmation without leaving the screen).
  bool _sent = false;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    // Drop the keyboard so the inline error/success is visible on small screens.
    FocusScope.of(context).unfocus();
    final outcome =
        await ref.read(supportTicketControllerProvider.notifier).submit(
              kind: _kind,
              message: _message.text,
            );
    if (!mounted) return;
    if (outcome == SupportTicketOutcome.sent) {
      setState(() => _sent = true);
    }
    // On error, state.error renders inline below (watched in build).
  }

  void _reset() {
    _message.clear();
    setState(() {
      _kind = SupportTicketKind.problem;
      _sent = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    final state = ref.watch(supportTicketControllerProvider);

    return Scaffold(
      backgroundColor: PgTokens.colorBg,
      appBar: PGuardHeader(
        light: true,
        title: isThai
            ? 'แจ้งปัญหา / ส่งความคิดเห็น'
            : 'Report a problem / feedback',
        subtitle: isThai ? 'เราจะรีบตรวจสอบให้' : 'We\'ll look into it',
        showBack: true,
      ),
      body: SafeArea(
        child: _sent
            ? _SentPanel(isThai: isThai, onAnother: _reset)
            : ListView(
                padding: const EdgeInsets.all(PgTokens.space4),
                children: [
                  Text(
                    isThai ? 'ประเภท' : 'Type',
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: PgTokens.space2),
                  _KindToggle(
                    kind: _kind,
                    isThai: isThai,
                    onChanged:
                        state.busy ? null : (k) => setState(() => _kind = k),
                  ),
                  const SizedBox(height: PgTokens.space4),
                  Text(
                    isThai ? 'ข้อความ' : 'Message',
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: PgTokens.space2),
                  TextField(
                    controller: _message,
                    enabled: !state.busy,
                    minLines: 5,
                    maxLines: 8,
                    maxLength: kMaxSupportTicketMessageLen,
                    textInputAction: TextInputAction.newline,
                    keyboardType: TextInputType.multiline,
                    inputFormatters: [
                      LengthLimitingTextInputFormatter(
                          kMaxSupportTicketMessageLen),
                    ],
                    decoration: InputDecoration(
                      hintText: _kind == SupportTicketKind.problem
                          ? (isThai
                              ? 'อธิบายปัญหาที่พบ…'
                              : 'Describe the problem…')
                          : (isThai
                              ? 'บอกความคิดเห็นของคุณ…'
                              : 'Share your feedback…'),
                      filled: true,
                      fillColor: PgTokens.colorSunken,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(PgTokens.radiusMd),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  if (state.error != null) ...[
                    const SizedBox(height: PgTokens.space2),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.error_outline,
                            size: 16, color: PgTokens.colorDanger),
                        const SizedBox(width: PgTokens.space2),
                        Expanded(
                          child: Text(
                            state.error!,
                            style: const TextStyle(
                                fontSize: 13, color: PgTokens.colorDanger),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: PgTokens.space5),
                  PgPrimaryButton(
                    label: isThai ? 'ส่ง' : 'Send',
                    busy: state.busy,
                    onPressed: state.busy ? null : _submit,
                  ),
                ],
              ),
      ),
    );
  }
}

/// The problem / feedback toggle (design `.segmented`). A two-option segmented control; the
/// selected pill is green. `onChanged` null → disabled (while a submit is in flight).
class _KindToggle extends StatelessWidget {
  const _KindToggle({
    required this.kind,
    required this.isThai,
    required this.onChanged,
  });

  final SupportTicketKind kind;
  final bool isThai;
  final ValueChanged<SupportTicketKind>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: PgTokens.colorSunken,
        borderRadius: BorderRadius.circular(PgTokens.radiusMd),
      ),
      child: Row(
        children: [
          _seg(SupportTicketKind.problem,
              isThai ? 'แจ้งปัญหา' : 'Report a problem'),
          _seg(SupportTicketKind.feedback,
              isThai ? 'ส่งความคิดเห็น' : 'Feedback'),
        ],
      ),
    );
  }

  Widget _seg(SupportTicketKind value, String label) {
    final selected = value == kind;
    return Expanded(
      child: GestureDetector(
        onTap: onChanged == null ? null : () => onChanged!(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? PgTokens.colorPrimary : Colors.transparent,
            borderRadius: BorderRadius.circular(PgTokens.radiusSm),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : PgTokens.colorTextMuted,
            ),
          ),
        ),
      ),
    );
  }
}

/// Post-submit confirmation — replaces the form so the ticket can't be double-filed. Offers a
/// "send another" reset (no navigation dead-end).
class _SentPanel extends StatelessWidget {
  const _SentPanel({required this.isThai, required this.onAnother});

  final bool isThai;
  final VoidCallback onAnother;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(PgTokens.space6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: PgTokens.colorGreen50,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_outline,
                  size: 34, color: PgTokens.colorPrimary),
            ),
            const SizedBox(height: PgTokens.space4),
            Text(
              isThai ? 'ส่งเรียบร้อยแล้ว' : 'Sent — thank you',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: PgTokens.space2),
            Text(
              isThai
                  ? 'ขอบคุณสำหรับข้อมูล ทีมงานจะตรวจสอบให้เร็วที่สุด'
                  : 'Thanks for letting us know — our team will review it soon.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 13.5, height: 1.6, color: PgTokens.colorTextMuted),
            ),
            const SizedBox(height: PgTokens.space5),
            PgGhostButton(
              label: isThai ? 'ส่งอีกครั้ง' : 'Send another',
              onPressed: onAnother,
            ),
          ],
        ),
      ),
    );
  }
}
