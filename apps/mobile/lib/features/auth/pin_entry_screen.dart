import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../core/controllers/auth_controller.dart';
import '../../core/controllers/registration_controller.dart';
import '../../widgets/pguard_header.dart';
import '../../widgets/pin_dots.dart';
import '../../widgets/pin_keypad.dart';

/// Step 3: set a 6-digit PIN. The PIN is the account credential — its SHA-256 is what
/// `POST /auth/register` stores (and `POST /auth/login` later verifies). After 6 digits we hand
/// the phone + phone-verified token + PIN to the registration flow and go to role selection;
/// registration (and the 409→login fallback for a returning user) happens there.
class PinEntryScreen extends ConsumerStatefulWidget {
  const PinEntryScreen({super.key});

  @override
  ConsumerState<PinEntryScreen> createState() => _PinEntryScreenState();
}

class _PinEntryScreenState extends ConsumerState<PinEntryScreen> {
  static const int _len = 6;
  String _pin = '';

  void _onDigit(String d) {
    if (_pin.length >= _len) return;
    setState(() => _pin += d);
    if (_pin.length == _len) {
      final auth = ref.read(authControllerProvider);
      ref.read(registrationControllerProvider.notifier).beginFromAuth(
            phone: auth.phone,
            phoneVerifiedToken: auth.phoneVerifiedToken,
            pin: _pin,
          );
      context.push('/auth/role');
      // Clear so returning to this screen starts fresh.
      setState(() => _pin = '');
    }
  }

  void _onBackspace() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const PGuardHeader(
          title: 'ตั้งรหัส PIN',
          subtitle: 'Create your 6-digit PIN',
          showBack: true),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: PgTokens.space7),
            const Text(
              'ตั้งรหัส PIN 6 หลัก',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: PgTokens.space2),
            const Text(
              'ใช้รหัสนี้เข้าสู่ระบบและปลดล็อกครั้งถัดไป',
              style: TextStyle(color: PgTokens.colorTextMuted, fontSize: 13),
            ),
            const SizedBox(height: PgTokens.space6),
            PinDots(length: _len, filled: _pin.length),
            const SizedBox(height: PgTokens.space3),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: PgTokens.space6),
              child: PinKeypad(
                enabled: true,
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
