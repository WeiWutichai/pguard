/// Pure exponential-backoff policy for WebSocket reconnects. No timers, no IO — just the
/// delay math, so it is fully unit-testable. The socket layer applies the returned delay
/// with a single one-shot timer (never `Timer.periodic` — this is push, not polling).
class BackoffPolicy {
  const BackoffPolicy({
    this.initial = const Duration(seconds: 1),
    this.max = const Duration(seconds: 60),
    this.factor = 2.0,
  });

  /// Delay before the first retry.
  final Duration initial;

  /// Hard cap on the delay (CLAUDE.md: cap 60s).
  final Duration max;

  /// Multiplier applied per attempt.
  final double factor;

  /// Delay before retry number [attempt] (0-based: attempt 0 is the first reconnect).
  /// Grows `initial * factor^attempt`, clamped to [max]. Deterministic (no jitter) so the
  /// schedule is testable; the caller may add jitter if desired.
  Duration delayFor(int attempt) {
    if (attempt < 0) attempt = 0;
    final millis = initial.inMilliseconds * _pow(factor, attempt);
    final capped = millis.isFinite ? millis : max.inMilliseconds.toDouble();
    final clamped = capped.clamp(0, max.inMilliseconds.toDouble());
    return Duration(milliseconds: clamped.round());
  }

  static double _pow(double base, int exp) {
    var result = 1.0;
    for (var i = 0; i < exp; i++) {
      result *= base;
      if (!result.isFinite) break;
    }
    return result;
  }
}
