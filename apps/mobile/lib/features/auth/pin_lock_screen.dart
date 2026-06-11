import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../core/controllers/pin_service.dart';
import '../../core/controllers/resend_policy.dart';
import '../../core/controllers/session_controller.dart';
import '../../core/providers.dart';
import '../../widgets/pguard_header.dart';
import '../../widgets/pin_dots.dart';
import '../../widgets/pin_keypad.dart';
import '../../widgets/primary_button.dart';

/// Returning-user lock screen: verify the local PIN OFFLINE (no network) via [PinService],
/// applying the 60s lockout (every 5 wrong) + on-device wipe (10 wrong). UI per the lock/
/// lockout/wipe screens (⑧–⑩) in `Mobile - Auth.html`: green welcome hero normally; during a
/// lockout the hero flips to the danger state, the dots dim, and a big m:ss countdown sits
/// between the warning and wipe-warning alerts. The 10th wrong PIN shows the data-wipe dialog
/// before dropping back to sign-in.
class PinLockScreen extends ConsumerStatefulWidget {
  const PinLockScreen({super.key});

  @override
  ConsumerState<PinLockScreen> createState() => _PinLockScreenState();
}

class _PinLockScreenState extends ConsumerState<PinLockScreen> {
  static const int _len = 6;
  String _pin = '';
  bool _busy = false;
  String? _error;
  int? _attemptsRemaining;
  DateTime? _lockedUntil; // local deadline for the display countdown

  bool get _isLocked =>
      _lockedUntil != null && _lockedUntil!.isAfter(DateTime.now().toUtc());

  Future<void> _onDigit(String d) async {
    if (_busy || _isLocked || _pin.length >= _len) return;
    setState(() => _pin += d);
    if (_pin.length == _len) await _verify();
  }

  void _onBackspace() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _verify() async {
    setState(() => _busy = true);
    final outcome = await ref.read(pinServiceProvider).verify(_pin);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _pin = '';
      switch (outcome.kind) {
        case PinOutcomeKind.success:
          _error = null;
        case PinOutcomeKind.wrong:
          _attemptsRemaining = outcome.attemptsRemaining;
          _error = 'PIN ไม่ถูกต้อง · เหลือ ${outcome.attemptsRemaining} ครั้ง';
        case PinOutcomeKind.lockedOut:
          // The locking attempt itself consumed one try (the service only reports
          // attemptsRemaining on `wrong`); 5 is the design's first-lockout value.
          _attemptsRemaining =
              _attemptsRemaining != null ? _attemptsRemaining! - 1 : 5;
          _lockedUntil = DateTime.now().toUtc().add(
                outcome.lockoutRemaining ?? const Duration(seconds: 60),
              );
          _error = null;
        case PinOutcomeKind.wiped:
          _error = null;
      }
    });
    switch (outcome.kind) {
      case PinOutcomeKind.success:
        ref.read(sessionProvider.notifier).onUnlocked();
      case PinOutcomeKind.wiped:
        // Too many attempts — local data wiped; explain (design screen ⑩) then sign out.
        await _showWipedDialog();
      default:
        break;
    }
  }

  /// Design screen ⑩: non-dismissable "data wiped" dialog, then back to sign-in.
  Future<void> _showWipedDialog() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: PgTokens.colorBrand.withValues(alpha: 0.6),
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: Dialog(
          backgroundColor: PgTokens.colorSurface,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: PgTokens.space6),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(PgTokens.radius2xl)),
          child: Padding(
            padding: const EdgeInsets.all(PgTokens.space6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: const BoxDecoration(
                      color: PgTokens.colorDangerBg, shape: BoxShape.circle),
                  child: const Icon(Icons.delete_outline,
                      size: 32, color: PgTokens.colorDanger),
                ),
                const SizedBox(height: PgTokens.space4),
                const Text(
                  'ข้อมูลในเครื่องจะถูกล้าง / On-device data will be wiped',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: PgTokens.space2),
                const Text(
                  'ใส่ PIN ผิดครบ 10 ครั้ง เพื่อความปลอดภัย ข้อมูลและเซสชันในเครื่องนี้จะถูกลบ คุณต้องเข้าสู่ระบบใหม่',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13.5, color: PgTokens.colorTextMuted),
                ),
                const SizedBox(height: PgTokens.space6),
                PgPrimaryButton(
                  label: 'เข้าสู่ระบบใหม่ / Sign in again',
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!mounted) return;
    await ref.read(sessionProvider.notifier).logout();
  }

  /// "ลืม PIN?" — confirm, then sign out to re-authenticate by phone/OTP (existing plumbing).
  Future<void> _forgotPin() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: PgTokens.colorSurface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(PgTokens.radius2xl)),
        title: const Text('ลืม PIN? / Forgot PIN?',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        content: const Text(
          'ต้องออกจากระบบและยืนยันเบอร์โทรอีกครั้งเพื่อตั้ง PIN ใหม่ / Sign out and verify your phone again to set a new PIN',
          style: TextStyle(fontSize: 13.5, color: PgTokens.colorTextMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('ยกเลิก / Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: PgTokens.colorDanger),
            child: const Text('ออกจากระบบ / Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref.read(sessionProvider.notifier).logout();
  }

  @override
  Widget build(BuildContext context) {
    final locked = _isLocked;
    return Scaffold(
      appBar: const PGuardHeader(title: 'ปลดล็อก', subtitle: 'Enter your PIN'),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: PgTokens.space6),
                child: Column(
                  children: [
                    const SizedBox(height: PgTokens.space7),
                    _hero(locked),
                    const SizedBox(height: PgTokens.space6),
                    // Design lockout state dims the dots (interaction already disabled).
                    Opacity(
                      opacity: locked ? 0.4 : 1,
                      child: PinDots(
                          length: _len,
                          filled: _pin.length,
                          error: _error != null),
                    ),
                    const SizedBox(height: PgTokens.space3),
                    _statusArea(),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: PgTokens.space6),
              child: PinKeypad(
                enabled: !_busy && !locked,
                onDigit: _onDigit,
                onBackspace: _onBackspace,
              ),
            ),
            PgGhostButton(
              label: 'ลืม PIN? / Forgot PIN?',
              onPressed: _busy ? null : _forgotPin,
            ),
            const SizedBox(height: PgTokens.space4),
          ],
        ),
      ),
    );
  }

  /// Welcome hero (design screen ⑧) — flips to the danger variant during a lockout (screen ⑨).
  /// No cached display name exists yet, so the avatar falls back to the person glyph rather
  /// than rendering meaningless JWT-UUID initials.
  Widget _hero(bool locked) {
    if (locked) {
      return const Column(
        children: [
          CircleAvatar(
            radius: 36,
            backgroundColor: PgTokens.colorDangerBg,
            child:
                Icon(Icons.lock_outline, size: 32, color: PgTokens.colorDanger),
          ),
          SizedBox(height: PgTokens.space3),
          Text('ใส่ PIN ผิดหลายครั้ง / Too many attempts',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        ],
      );
    }
    return const Column(
      children: [
        CircleAvatar(
          radius: 36,
          backgroundColor: PgTokens.colorGreen100,
          child:
              Icon(Icons.person_outline, size: 32, color: PgTokens.colorGreen800),
        ),
        SizedBox(height: PgTokens.space3),
        Text('ยินดีต้อนรับกลับ / Welcome back',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        SizedBox(height: PgTokens.space2),
        Text('กรอก PIN เพื่อเข้าสู่ระบบ / Enter your PIN to sign in',
            textAlign: TextAlign.center,
            style: TextStyle(color: PgTokens.colorTextMuted, fontSize: 13)),
      ],
    );
  }

  Widget _statusArea() {
    if (_isLocked) {
      return _LockoutPanel(
        until: _lockedUntil!,
        onElapsed: () => setState(() => _lockedUntil = null),
        attemptsRemaining: _attemptsRemaining ?? 5,
      );
    }
    if (_error != null) {
      return Text(_error!, style: const TextStyle(color: PgTokens.colorDanger));
    }
    return const SizedBox(height: 20);
  }
}

/// Lockout state (design screen ⑨): amber warning alert, the big danger m:ss countdown, and the
/// red wipe-warning alert. Live countdown is a display ticker (not polling); calls [onElapsed]
/// when the window ends so the keypad re-enables.
class _LockoutPanel extends StatelessWidget {
  const _LockoutPanel(
      {required this.until,
      required this.onElapsed,
      required this.attemptsRemaining});

  final DateTime until;
  final VoidCallback onElapsed;
  final int attemptsRemaining;

  static const ResendPolicy _format = ResendPolicy();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: Stream<int>.periodic(const Duration(seconds: 1), (i) => i),
      builder: (context, _) {
        final remaining = until.difference(DateTime.now().toUtc());
        if (remaining <= Duration.zero) {
          WidgetsBinding.instance.addPostFrameCallback((_) => onElapsed());
          return const SizedBox(height: 20);
        }
        return Column(
          children: [
            const _LockAlert(
              background: PgTokens.colorWarningBg,
              foreground: PgTokens.colorAmber700,
              icon: Icons.warning_amber_rounded,
              strong: 'ผิด 5 ครั้ง — ล็อกชั่วคราว',
              body: 'ลองใหม่อีกครั้งเมื่อหมดเวลา',
            ),
            // Big danger countdown (design `.timer-big`: 40/600 mono m:ss, 8px vertical padding).
            Padding(
              padding: const EdgeInsets.symmetric(vertical: PgTokens.space2),
              child: Text(
                _format.format(remaining.inSeconds),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'IBMPlexMono',
                  fontFeatures: [FontFeature.tabularFigures()],
                  color: PgTokens.colorDanger,
                ),
              ),
            ),
            const SizedBox(height: 10),
            _LockAlert(
              background: PgTokens.colorDangerBg,
              foreground: PgTokens.colorDanger,
              icon: Icons.info_outline,
              strong: 'คำเตือน: เหลืออีก $attemptsRemaining ครั้ง',
              body: 'หากผิดครบ 10 ครั้ง ข้อมูลในเครื่องจะถูกล้าง',
            ),
          ],
        );
      },
    );
  }
}

/// One design alert row: tinted background, 18px icon, bold first line + regular second line.
class _LockAlert extends StatelessWidget {
  const _LockAlert({
    required this.background,
    required this.foreground,
    required this.icon,
    required this.strong,
    required this.body,
  });

  final Color background;
  final Color foreground;
  final IconData icon;
  final String strong;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(PgTokens.space4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(PgTokens.radiusXl),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: foreground),
          const SizedBox(width: PgTokens.space2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(strong,
                    style: TextStyle(
                        color: foreground,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                Text(body, style: TextStyle(color: foreground, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
