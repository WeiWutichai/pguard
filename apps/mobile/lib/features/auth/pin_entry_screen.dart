import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../core/controllers/auth_controller.dart';
import '../../core/controllers/locale_controller.dart';
import '../../core/controllers/registration_controller.dart';
import '../../widgets/auth_head.dart';
import '../../widgets/pg_auth_back_bar.dart';
import '../../widgets/pin_dots.dart';
import '../../widgets/pin_keypad.dart';

/// Step 3: set a 6-digit PIN, then re-enter it to confirm (design screens ③+④ — lock-tile hero,
/// strength feedback under the dots, mismatch → error dots and retry). The PIN is the account
/// credential — its SHA-256 is what `POST /auth/register` stores (and `POST /auth/login` later
/// verifies). After the confirm matches we hand the phone + phone-verified token + PIN to the
/// registration flow and go to role selection; registration (and the 409→login fallback for a
/// returning user) happens there.
class PinEntryScreen extends ConsumerStatefulWidget {
  const PinEntryScreen({super.key});

  @override
  ConsumerState<PinEntryScreen> createState() => _PinEntryScreenState();
}

class _PinEntryScreenState extends ConsumerState<PinEntryScreen> {
  static const int _len = 6;
  String _pin = '';

  /// Phase 1 result; non-null = we're on the confirm step (design screen ④).
  String? _firstPin;

  /// Confirm didn't match — show error dots until the next key press.
  bool _mismatch = false;

  bool get _confirming => _firstPin != null;

  void _onDigit(String d) {
    if (_pin.length >= _len) return;
    setState(() {
      _mismatch = false;
      _pin += d;
    });
    if (_pin.length < _len) return;
    if (!_confirming) {
      // Phase 1 done → clear the dots and ask to re-enter (ยืนยันรหัส PIN อีกครั้ง).
      setState(() {
        _firstPin = _pin;
        _pin = '';
      });
      return;
    }
    if (_pin != _firstPin) {
      // Design screen ④ mismatch: dots flip to the danger state, entry resets.
      setState(() {
        _mismatch = true;
        _pin = '';
      });
      return;
    }
    final auth = ref.read(authControllerProvider);
    ref.read(registrationControllerProvider.notifier).beginFromAuth(
          phone: auth.phone,
          phoneVerifiedToken: auth.phoneVerifiedToken,
          pin: _pin,
        );
    context.push('/auth/role');
    // Clear so returning to this screen starts fresh.
    setState(() {
      _pin = '';
      _firstPin = null;
      _mismatch = false;
    });
  }

  void _onBackspace() {
    if (_pin.isEmpty) return;
    setState(() {
      _mismatch = false;
      _pin = _pin.substring(0, _pin.length - 1);
    });
  }

  /// Back from the confirm step returns to phase 1 (per design), not out of the screen.
  void _backToFirstEntry() {
    setState(() {
      _firstPin = null;
      _pin = '';
      _mismatch = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    return PopScope(
      canPop: !_confirming,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _backToFirstEntry();
      },
      child: Scaffold(
        // No green bar (hi-fi has none; the "ตั้งรหัส PIN" title is the body AuthHead).
        // Keep the confirm→first-entry back behavior on the transparent back chevron.
        appBar: PgAuthBackBar(
          onBack: _confirming ? _backToFirstEntry : null,
        ),
        body: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: PgTokens.space7),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: PgTokens.space6),
                child: AuthHead(
                  icon: const AuthHeadIconTile(icon: Icons.lock_outline),
                  title: _confirming
                      ? (isThai
                          ? 'ยืนยันรหัส PIN อีกครั้ง'
                          : 'Re-enter your PIN')
                      : 'ตั้งรหัส PIN 6 หลัก',
                  subtitle: _confirming
                      ? (isThai ? 'เพื่อความถูกต้อง' : 'To confirm it matches')
                      : (isThai
                          ? 'ใช้เข้าแอปครั้งต่อไป'
                          : 'You\'ll use this to sign in'),
                ),
              ),
              const SizedBox(height: PgTokens.space6),
              PinDots(
                length: _len,
                filled: _mismatch ? _len : _pin.length,
                error: _mismatch,
              ),
              const SizedBox(height: PgTokens.space3),
              _strengthFeedback(isThai),
              const Spacer(),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: PgTokens.space6),
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
      ),
    );
  }

  /// Design screen ③ security feedback under the dots: green "good" line while the PIN avoids
  /// repeated/sequential digits, warning nudge otherwise (pure check — [AuthController.isWeakPin]).
  Widget _strengthFeedback(bool isThai) {
    if (_confirming || _pin.isEmpty) return const SizedBox(height: 18);
    final weak = AuthController.isWeakPin(_pin);
    return Text(
      weak
          ? (isThai ? 'หลีกเลี่ยงเลขซ้ำ' : 'Avoid repeated digits')
          : (isThai
              ? 'ความปลอดภัยดี · หลีกเลี่ยงเลขซ้ำ'
              : 'Good · avoid repeated digits'),
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        color: weak ? PgTokens.colorWarning : PgTokens.colorSuccess,
      ),
    );
  }
}
