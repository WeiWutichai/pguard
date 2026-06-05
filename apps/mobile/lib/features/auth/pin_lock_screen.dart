import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../core/controllers/pin_service.dart';
import '../../core/controllers/session_controller.dart';
import '../../core/providers.dart';
import '../../widgets/pguard_header.dart';
import '../../widgets/pin_dots.dart';
import '../../widgets/pin_keypad.dart';

/// Returning-user lock screen: verify the local PIN OFFLINE (no network) via [PinService],
/// applying the 60s lockout (every 5 wrong) + on-device wipe (10 wrong). UI per the lock/
/// lockout screens in `Mobile - Auth.html`.
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
          ref.read(sessionProvider.notifier).onUnlocked();
        case PinOutcomeKind.wrong:
          _attemptsRemaining = outcome.attemptsRemaining;
          _error = 'PIN ไม่ถูกต้อง · เหลือ ${outcome.attemptsRemaining} ครั้ง';
        case PinOutcomeKind.lockedOut:
          _lockedUntil = DateTime.now().toUtc().add(
                outcome.lockoutRemaining ?? const Duration(seconds: 60),
              );
          _error = null;
        case PinOutcomeKind.wiped:
          // Too many attempts — local data wiped; drop the session back to sign-in.
          ref.read(sessionProvider.notifier).logout();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(sessionProvider).user;

    return Scaffold(
      appBar: const PGuardHeader(title: 'ปลดล็อก', subtitle: 'Enter your PIN'),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: PgTokens.space7),
            CircleAvatar(
              radius: 36,
              backgroundColor: PgTokens.colorGreen100,
              child: Text(
                _initials(user?.userId),
                style: const TextStyle(
                  color: PgTokens.colorGreen800,
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: PgTokens.space3),
            const Text('ยินดีต้อนรับกลับมา',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: PgTokens.space2),
            const Text('ใส่ PIN เพื่อเข้าใช้งาน · Enter PIN',
                style: TextStyle(color: PgTokens.colorTextMuted, fontSize: 13)),
            const SizedBox(height: PgTokens.space6),
            PinDots(length: _len, filled: _pin.length, error: _error != null),
            const SizedBox(height: PgTokens.space3),
            _statusArea(),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: PgTokens.space6),
              child: PinKeypad(
                enabled: !_busy && !_isLocked,
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

  Widget _statusArea() {
    if (_isLocked) {
      return _LockoutBanner(
        until: _lockedUntil!,
        onElapsed: () => setState(() => _lockedUntil = null),
        attemptsRemaining: _attemptsRemaining,
      );
    }
    if (_error != null) {
      return Text(_error!, style: const TextStyle(color: PgTokens.colorDanger));
    }
    return const SizedBox(height: 20);
  }

  static String _initials(String? id) {
    if (id == null || id.isEmpty) return '••';
    return id.substring(0, id.length >= 2 ? 2 : 1).toUpperCase();
  }
}

/// Lockout warning + live countdown (display ticker — not polling). Calls [onElapsed] when
/// the window ends so the keypad re-enables.
class _LockoutBanner extends StatelessWidget {
  const _LockoutBanner(
      {required this.until, required this.onElapsed, this.attemptsRemaining});

  final DateTime until;
  final VoidCallback onElapsed;
  final int? attemptsRemaining;

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
        final secs = remaining.inSeconds;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: PgTokens.space6),
          padding: const EdgeInsets.all(PgTokens.space4),
          decoration: BoxDecoration(
            color: PgTokens.colorWarningBg,
            borderRadius: BorderRadius.circular(PgTokens.radiusXl),
          ),
          child: Column(
            children: [
              Text(
                'PIN ผิดหลายครั้ง — ล็อก ${secs}s',
                style: const TextStyle(
                    color: PgTokens.colorAmber700, fontWeight: FontWeight.w600),
              ),
              if (attemptsRemaining != null)
                const Text(
                  'หลังจากนี้ครบ 10 ครั้งจะลบข้อมูลในเครื่อง',
                  style: TextStyle(color: PgTokens.colorAmber700, fontSize: 12),
                ),
            ],
          ),
        );
      },
    );
  }
}
