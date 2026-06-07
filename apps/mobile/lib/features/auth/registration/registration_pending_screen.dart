import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../../core/controllers/registration_controller.dart';
import '../../../core/models/registration.dart';
import '../../../core/providers.dart';
import '../../../widgets/pguard_header.dart';
import '../../../widgets/primary_button.dart';

/// Shown after the profile is submitted: the account is registered but PENDING approval (no
/// tokens, can't log in yet). Renders the submitted summary and a "check status" action that
/// attempts `loginWithPin` — which succeeds only once the account is approved (then the session
/// flips to authenticated and the router redirects to the dashboard); otherwise it stays pending.
/// There is no editing of a submitted profile (v2).
class RegistrationPendingScreen extends ConsumerStatefulWidget {
  const RegistrationPendingScreen({super.key});

  @override
  ConsumerState<RegistrationPendingScreen> createState() =>
      _RegistrationPendingScreenState();
}

class _RegistrationPendingScreenState
    extends ConsumerState<RegistrationPendingScreen> {
  RegistrationSummary? _summary;

  @override
  void initState() {
    super.initState();
    // Live flow: the summary is on the controller. Cold start (fresh keepAlive controller): load
    // the masked summary persisted to prefs at submit.
    _summary = ref.read(registrationControllerProvider).submitted;
    if (_summary == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadFromPrefs());
    }
  }

  Future<void> _loadFromPrefs() async {
    final raw = await ref.read(prefsStoreProvider).getString(kRegSummaryKey);
    if (raw == null || raw.isEmpty || !mounted) return;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final parsed = RegistrationSummary.tryFromJson(json);
      if (parsed != null && mounted) setState(() => _summary = parsed);
    } catch (_) {
      // Ignore a corrupt cached summary — the pending state is still valid.
    }
  }

  Future<void> _checkStatus() async {
    final ctrl = ref.read(registrationControllerProvider.notifier);
    final approved = ctrl.canCheckSilently
        ? await ctrl.checkStatus()
        : await _checkWithReenteredPin(ctrl);
    if (!mounted || approved == null) return;
    // approved == true → session is now authenticated; the router redirects automatically.
    if (!approved) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('ยังรอการอนุมัติอยู่ / Still pending approval'),
      ));
    }
  }

  /// Cold start: the in-memory PIN is gone, so re-enter it to attempt the approved-login.
  Future<bool?> _checkWithReenteredPin(RegistrationController ctrl) async {
    final controller = TextEditingController();
    final pin = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ใส่ PIN เพื่อตรวจสอบ / Enter PIN'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          obscureText: true,
          maxLength: 6,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(hintText: '••••••'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('ยกเลิก / Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('ตรวจสอบ / Check'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (pin == null || pin.length != 6) return null;
    return ctrl.checkStatusWithPin(pin);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(registrationControllerProvider);
    final summary = _summary;
    final isGuard = summary?.role.isGuard ?? false;

    return Scaffold(
      appBar: const PGuardHeader(
        title: 'รอการอนุมัติ',
        subtitle: 'Pending approval',
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(PgTokens.space6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: PgTokens.space4),
              const Icon(Icons.hourglass_top,
                  size: 56, color: PgTokens.colorWarning),
              const SizedBox(height: PgTokens.space4),
              Text(
                isGuard
                    ? 'ส่งข้อมูลแล้ว · รอแอดมินตรวจสอบ'
                    : 'สมัครเรียบร้อย · รอการยืนยัน',
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: PgTokens.space2),
              const Text(
                'จะเข้าสู่ระบบได้เมื่อได้รับการอนุมัติ\n'
                "You can sign in once your account is approved",
                textAlign: TextAlign.center,
                style: TextStyle(color: PgTokens.colorTextMuted),
              ),
              const SizedBox(height: PgTokens.space6),
              if (summary != null) _SummaryCard(summary: summary),
              const SizedBox(height: PgTokens.space6),
              PgPrimaryButton(
                label: 'ตรวจสอบสถานะ / Check status',
                busy: state.busy,
                onPressed: state.busy ? null : _checkStatus,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary});

  final RegistrationSummary summary;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(PgTokens.space4),
      decoration: BoxDecoration(
        color: PgTokens.colorSunken,
        borderRadius: BorderRadius.circular(PgTokens.radiusXl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            summary.role.isGuard
                ? 'ข้อมูลที่ส่ง · เจ้าหน้าที่'
                : 'ข้อมูลที่ส่ง · ลูกค้า',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: PgTokens.space3),
          for (final line in summary.lines)
            Padding(
              padding: const EdgeInsets.only(bottom: PgTokens.space2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 130,
                    child: Text(line.label,
                        style: const TextStyle(
                            color: PgTokens.colorTextMuted, fontSize: 13)),
                  ),
                  Expanded(
                      child: Text(line.value,
                          style: const TextStyle(fontSize: 14))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
