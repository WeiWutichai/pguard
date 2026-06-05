/// PURE PIN lockout/wipe policy — no storage, no Flutter, fully unit-testable. Ported from
/// v1's pin_storage_service semantics: 6-digit PIN, 60-second lockout every 5 wrong attempts,
/// on-device wipe after 10 cumulative wrong attempts.
class PinPolicy {
  const PinPolicy({
    this.pinLength = 6,
    this.lockoutWindow = 5,
    this.lockoutDuration = const Duration(seconds: 60),
    this.wipeThreshold = 10,
  });

  final int pinLength;

  /// A lockout is imposed each time wrong attempts reach a multiple of this.
  final int lockoutWindow;
  final Duration lockoutDuration;

  /// Cumulative wrong attempts that trigger an on-device data wipe.
  final int wipeThreshold;

  bool isValidFormat(String pin) =>
      pin.length == pinLength && RegExp(r'^\d+$').hasMatch(pin);

  /// Remaining lockout at [now] from a stored deadline (epoch ms, UTC); `null` if not locked.
  Duration? remainingLockout(int? lockUntilMs, DateTime now) {
    if (lockUntilMs == null) return null;
    final until = DateTime.fromMillisecondsSinceEpoch(lockUntilMs, isUtc: true);
    final diff = until.difference(now.toUtc());
    return diff > Duration.zero ? diff : null;
  }

  /// Decide the consequence of a WRONG PIN entry given the prior wrong-attempt count.
  PinDecision afterWrongAttempt(int priorAttempts, DateTime now) {
    final attempts = priorAttempts + 1;
    if (attempts >= wipeThreshold) {
      return PinDecision(
        newAttempts: attempts,
        shouldWipe: true,
        attemptsRemaining: 0,
      );
    }
    final shouldLock = attempts % lockoutWindow == 0;
    final lockUntilMs = shouldLock
        ? now.toUtc().add(lockoutDuration).millisecondsSinceEpoch
        : null;
    return PinDecision(
      newAttempts: attempts,
      lockUntilMs: lockUntilMs,
      attemptsRemaining: wipeThreshold - attempts,
    );
  }
}

/// The outcome of a wrong-PIN attempt.
class PinDecision {
  const PinDecision({
    required this.newAttempts,
    this.lockUntilMs,
    this.shouldWipe = false,
    required this.attemptsRemaining,
  });

  final int newAttempts;
  final int? lockUntilMs;
  final bool shouldWipe;
  final int attemptsRemaining;

  bool get locked => lockUntilMs != null;
}
