import 'dart:async';

import '../storage/secure_store.dart';
import 'pin_hasher.dart';
import 'pin_policy.dart';

/// The result of a PIN verification attempt.
enum PinOutcomeKind { success, wrong, lockedOut, wiped }

class PinOutcome {
  const PinOutcome(
    this.kind, {
    this.attemptsRemaining,
    this.lockoutRemaining,
  });

  final PinOutcomeKind kind;

  /// Wrong attempts left before wipe (for the `wrong` outcome).
  final int? attemptsRemaining;

  /// Remaining lockout window (for the `lockedOut` outcome).
  final Duration? lockoutRemaining;

  bool get isSuccess => kind == PinOutcomeKind.success;
}

/// Storage-backed PIN gate. Combines the pure [PinPolicy] (lockout/wipe math) + [PinHasher]
/// (salted SHA-256) over a [PinStore]. Concurrent [verify] calls are serialized so rapid
/// double-taps can't corrupt the attempt counter (mirrors v1's Completer serialization).
/// Testable: inject an in-memory [PinStore], a fixed clock, and a deterministic salt.
class PinService {
  PinService({
    required PinStore store,
    this.policy = const PinPolicy(),
    this.hasher = const PinHasher(),
    DateTime Function()? clock,
  })  : _store = store,
        _clock = clock ?? (() => DateTime.now().toUtc());

  final PinStore _store;
  final PinPolicy policy;
  final PinHasher hasher;
  final DateTime Function() _clock;

  Future<void> _lock = Future<void>.value();

  Future<bool> hasPin() => _store.hasPin();

  /// Validate format and store a salted hash, resetting any prior lockout state.
  Future<bool> setup(String pin) async {
    if (!policy.isValidFormat(pin)) return false;
    final salt = hasher.generateSalt();
    final hash = hasher.hash(pin, salt);
    await _store.savePin(hash: hash, salt: salt);
    return true;
  }

  /// Verify a PIN, applying lockout + wipe rules. Serialized against concurrent calls.
  Future<PinOutcome> verify(String pin) {
    final result = _lock.then((_) => _verifyLocked(pin));
    // Keep the chain alive even if this attempt throws.
    _lock = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<PinOutcome> _verifyLocked(String pin) async {
    final now = _clock();
    final lockRemaining =
        policy.remainingLockout(await _store.readPinLockUntilMs(), now);
    if (lockRemaining != null) {
      return PinOutcome(PinOutcomeKind.lockedOut,
          lockoutRemaining: lockRemaining);
    }

    final hash = await _store.readPinHash();
    final salt = await _store.readPinSalt();
    if (hash != null && salt != null && hasher.verify(pin, salt, hash)) {
      await _store.resetPinAttempts();
      return const PinOutcome(PinOutcomeKind.success);
    }

    // Wrong PIN → advance lockout/wipe state machine.
    final prior = await _store.readPinAttempts();
    final decision = policy.afterWrongAttempt(prior, now);
    if (decision.shouldWipe) {
      await _store.wipe();
      return const PinOutcome(PinOutcomeKind.wiped);
    }
    await _store.writePinAttempts(decision.newAttempts);
    if (decision.locked) {
      await _store.writePinLockUntilMs(decision.lockUntilMs);
      return PinOutcome(
        PinOutcomeKind.lockedOut,
        lockoutRemaining: policy.remainingLockout(decision.lockUntilMs, now),
      );
    }
    return PinOutcome(
      PinOutcomeKind.wrong,
      attemptsRemaining: decision.attemptsRemaining,
    );
  }
}
