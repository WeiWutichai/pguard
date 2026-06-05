import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../core/controllers/auth_controller.dart';
import '../../widgets/pguard_header.dart';
import '../../widgets/pin_dots.dart';
import '../../widgets/pin_keypad.dart';

/// Step 3: the 6-digit PIN signs in — `POST /auth/login { identifier: phone, password: pin }`
/// (v1's PIN-as-password). On success the session flips to authenticated and the router lands
/// on the role dashboard. UI per the PIN screens in `Mobile - Auth.html`.
class PinEntryScreen extends ConsumerStatefulWidget {
  const PinEntryScreen({super.key});

  @override
  ConsumerState<PinEntryScreen> createState() => _PinEntryScreenState();
}

class _PinEntryScreenState extends ConsumerState<PinEntryScreen> {
  static const int _len = 6;
  String _pin = '';

  Future<void> _onDigit(String d) async {
    if (_pin.length >= _len) return;
    setState(() => _pin += d);
    if (_pin.length == _len) {
      final ok =
          await ref.read(authControllerProvider.notifier).loginWithPin(_pin);
      // wrong creds → clear and show error; success → session authenticated, router redirects.
      if (!ok && mounted) {
        setState(() => _pin = '');
      }
    }
  }

  void _onBackspace() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authControllerProvider);

    return Scaffold(
      appBar: const PGuardHeader(
          title: 'ตั้ง PIN เข้าสู่ระบบ',
          subtitle: 'Enter PIN to sign in',
          showBack: true),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: PgTokens.space7),
            const Text(
              'ใส่รหัส PIN 6 หลัก',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: PgTokens.space2),
            const Text(
              'PIN นี้ใช้เข้าสู่ระบบและปลดล็อกครั้งถัดไป',
              style: TextStyle(color: PgTokens.colorTextMuted, fontSize: 13),
            ),
            const SizedBox(height: PgTokens.space6),
            PinDots(
                length: _len, filled: _pin.length, error: state.error != null),
            const SizedBox(height: PgTokens.space3),
            SizedBox(
              height: 20,
              child: state.busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : (state.error != null
                      ? Text(state.error!,
                          style: const TextStyle(color: PgTokens.colorDanger))
                      : null),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: PgTokens.space6),
              child: PinKeypad(
                enabled: !state.busy,
                onDigit: _onDigit,
                onBackspace: _onBackspace,
              ),
            ),
            const SizedBox(height: PgTokens.space6),
          ],
        ),
      ),
    );
  }
}
