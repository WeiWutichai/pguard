import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../core/controllers/auth_controller.dart';
import '../../core/controllers/locale_controller.dart';
import '../../core/controllers/pin_service.dart';
import '../../core/controllers/resend_policy.dart';
import '../../core/controllers/session_controller.dart';
import '../../core/providers.dart';
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

  /// Whether to surface the biometric key (opted-in AND device still capable). Resolved async on
  /// open; the keypad's own `enabled` flag still gates it off during a lockout.
  bool _bioAvailable = false;

  /// Auto-prompt fires at most once per screen open; manual taps of the key can always retry.
  bool _bioPrompted = false;

  bool get _isLocked =>
      _lockedUntil != null && _lockedUntil!.isAfter(DateTime.now().toUtc());

  @override
  void initState() {
    super.initState();
    Future.microtask(_rehydrateLockThenInitBiometric);
  }

  /// Seed the lockout from persisted storage BEFORE offering biometric. After an app kill DURING a
  /// lockout the screen must present locked (countdown + disabled keypad) and the `_isLocked` guard
  /// in [_authenticateBiometric] must hold, so a biometric unlock can't skip the remaining window
  /// (deep-review — the UI otherwise presented fully unlocked on restart).
  Future<void> _rehydrateLockThenInitBiometric() async {
    final untilMs = await ref.read(appStoreProvider).readPinLockUntilMs();
    if (!mounted) return;
    if (untilMs != null) {
      final until = DateTime.fromMillisecondsSinceEpoch(untilMs, isUtc: true);
      if (until.isAfter(DateTime.now().toUtc())) {
        setState(() => _lockedUntil = until);
      }
    }
    await _initBiometric();
  }

  /// Show the biometric key when the user opted in and the device can still authenticate, then
  /// auto-prompt once (the standard unlock UX — design ⑦ "กรอก PIN หรือใช้ Face ID").
  Future<void> _initBiometric() async {
    final offer = await ref.read(biometricServiceProvider).shouldOffer();
    if (!mounted || !offer) return;
    setState(() => _bioAvailable = true);
    await _authenticateBiometric(auto: true);
  }

  /// Biometric unlock path: prompt the OS, and on success clear the gate. On cancel/failure the
  /// user simply falls back to the PIN keypad (no error noise). The OS rate-limits its own prompt.
  Future<void> _authenticateBiometric({bool auto = false}) async {
    if (_busy || _isLocked) return;
    if (auto && _bioPrompted) return;
    _bioPrompted = true;
    final isThai = ref.read(localeControllerProvider) == AppLocale.th;
    setState(() => _busy = true);
    final ok = await ref.read(biometricServiceProvider).authenticate(
          reason: isThai
              ? 'ปลดล็อก pguard ด้วยไบโอเมตริก'
              : 'Unlock pguard with biometrics',
        );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) ref.read(sessionProvider.notifier).onUnlocked();
  }

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
    final isThai = ref.read(localeControllerProvider) == AppLocale.th;
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
          _error = isThai
              ? 'PIN ไม่ถูกต้อง · เหลือ ${outcome.attemptsRemaining} ครั้ง'
              : 'Incorrect PIN · ${outcome.attemptsRemaining} left';
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
    final isThai = ref.read(localeControllerProvider) == AppLocale.th;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: PgTokens.colorBrand.withValues(alpha: 0.6),
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: Dialog(
          backgroundColor: PgTokens.colorSurface,
          insetPadding: const EdgeInsets.symmetric(horizontal: PgTokens.space6),
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
                Text(
                  isThai
                      ? 'ข้อมูลในเครื่องจะถูกล้าง'
                      : 'On-device data will be wiped',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: PgTokens.space2),
                // Thai-only body (no ' / ' language separator in the source) — left as-is per
                // the split rule; not translated.
                const Text(
                  'ใส่ PIN ผิดครบ 10 ครั้ง เพื่อความปลอดภัย ข้อมูลและเซสชันในเครื่องนี้จะถูกลบ คุณต้องเข้าสู่ระบบใหม่',
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(fontSize: 13.5, color: PgTokens.colorTextMuted),
                ),
                const SizedBox(height: PgTokens.space6),
                PgPrimaryButton(
                  label: isThai ? 'เข้าสู่ระบบใหม่' : 'Sign in again',
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!mounted) return;
    // The wipe already cleared the local PIN — forget the device fully so it starts fresh at OTP.
    await ref.read(sessionProvider.notifier).logout(forgetDevice: true);
  }

  /// "ลืม PIN?" — confirm, then RESET the PIN via OTP: verify the phone again and set a new PIN
  /// (`POST /auth/reset-pin`), keeping the account. Falls back to a full sign-out only if the device
  /// somehow has no remembered phone.
  Future<void> _forgotPin() async {
    final isThai = ref.read(localeControllerProvider) == AppLocale.th;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: PgTokens.colorSurface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(PgTokens.radius2xl)),
        title: Text(isThai ? 'ลืม PIN?' : 'Forgot PIN?',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        content: Text(
          isThai
              ? 'ยืนยันเบอร์โทรด้วย OTP อีกครั้ง เพื่อตั้งรหัส PIN ใหม่'
              : 'Verify your phone with an OTP again to set a new PIN',
          style:
              const TextStyle(fontSize: 13.5, color: PgTokens.colorTextMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(isThai ? 'ยกเลิก' : 'Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(isThai ? 'ตั้ง PIN ใหม่' : 'Reset PIN'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final phone = await ref.read(appStoreProvider).readPhone();
    if (!mounted) return;
    if (phone == null) {
      // No remembered phone → can't target the reset; fall back to a full sign-out.
      await ref.read(sessionProvider.notifier).logout(forgetDevice: true);
      return;
    }
    // Seed the reset run + move out of `locked` (into `returning`, which permits /auth/*), then
    // jump into the captcha → OTP → new-PIN flow. resetPin then logs in with the new PIN.
    ref.read(authControllerProvider.notifier).startReset(phone);
    ref.read(sessionProvider.notifier).beginPinReset();
    if (!mounted) return;
    context.go('/auth/captcha');
  }

  @override
  Widget build(BuildContext context) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    final locked = _isLocked;
    // No green bar — the returning-user screen's hero ("ยินดีต้อนรับกลับ") is the body head.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
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
                      _hero(locked, isThai),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: PgTokens.space6),
                child: PinKeypad(
                  enabled: !_busy && !locked,
                  onDigit: _onDigit,
                  onBackspace: _onBackspace,
                  onBiometric:
                      _bioAvailable ? () => _authenticateBiometric() : null,
                ),
              ),
              PgGhostButton(
                label: isThai ? 'ลืม PIN?' : 'Forgot PIN?',
                onPressed: _busy ? null : _forgotPin,
              ),
              const SizedBox(height: PgTokens.space4),
            ],
          ),
        ),
      ),
    );
  }

  /// Welcome hero (design screen ⑧) — flips to the danger variant during a lockout (screen ⑨).
  /// No cached display name exists yet, so the avatar falls back to the person glyph rather
  /// than rendering meaningless JWT-UUID initials.
  Widget _hero(bool locked, bool isThai) {
    if (locked) {
      return Column(
        children: [
          const CircleAvatar(
            radius: 36,
            backgroundColor: PgTokens.colorDangerBg,
            child:
                Icon(Icons.lock_outline, size: 32, color: PgTokens.colorDanger),
          ),
          const SizedBox(height: PgTokens.space3),
          Text(isThai ? 'ใส่ PIN ผิดหลายครั้ง' : 'Too many attempts',
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        ],
      );
    }
    return Column(
      children: [
        const CircleAvatar(
          radius: 36,
          backgroundColor: PgTokens.colorGreen100,
          child: Icon(Icons.person_outline,
              size: 32, color: PgTokens.colorGreen800),
        ),
        const SizedBox(height: PgTokens.space3),
        Text(isThai ? 'ยินดีต้อนรับกลับ' : 'Welcome back',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        const SizedBox(height: PgTokens.space2),
        Text(
            _bioAvailable
                ? (isThai
                    ? 'กรอก PIN หรือใช้ไบโอเมตริก'
                    : 'Enter PIN or use biometrics')
                : (isThai
                    ? 'กรอก PIN เพื่อเข้าสู่ระบบ'
                    : 'Enter your PIN to sign in'),
            textAlign: TextAlign.center,
            style:
                const TextStyle(color: PgTokens.colorTextMuted, fontSize: 13)),
      ],
    );
  }

  Widget _statusArea() {
    if (_isLocked) {
      return _LockoutPanel(
        until: _lockedUntil!,
        onElapsed: () => setState(() => _lockedUntil = null),
        attemptsRemaining: _attemptsRemaining ?? 5,
        isThai: ref.read(localeControllerProvider) == AppLocale.th,
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
      required this.attemptsRemaining,
      required this.isThai});

  final DateTime until;
  final VoidCallback onElapsed;
  final int attemptsRemaining;
  final bool isThai;

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
            _LockAlert(
              background: PgTokens.colorWarningBg,
              foreground: PgTokens.colorAmber700,
              icon: Icons.warning_amber_rounded,
              strong: isThai
                  ? 'ผิด 5 ครั้ง — ล็อกชั่วคราว'
                  : 'Locked temporarily — 5 wrong attempts',
              body: isThai
                  ? 'ลองใหม่อีกครั้งเมื่อหมดเวลา'
                  : 'Try again when the timer ends',
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
              strong: isThai
                  ? 'คำเตือน: เหลืออีก $attemptsRemaining ครั้ง'
                  : 'Warning: $attemptsRemaining attempts left',
              body: isThai
                  ? 'หากผิดครบ 10 ครั้ง ข้อมูลในเครื่องจะถูกล้าง'
                  : 'On-device data is wiped after 10 wrong attempts',
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
