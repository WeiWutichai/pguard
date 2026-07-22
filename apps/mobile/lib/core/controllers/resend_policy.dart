/// PURE OTP resend-cooldown logic — deadline based, no timers, fully unit-testable. The OTP
/// screen drives a 1-second display ticker; this computes what to show. (This is a UI
/// countdown, NOT the booking-status path — that is WebSocket push with zero polling.)
class ResendPolicy {
  // 180s (not 120s): the otp service trips a 10-min burst lock at 3 requests inside a 600s window
  // (services/otp/src/domain/lockout.rs). A slower resend cadence spaces attempts so a user chasing
  // a delayed SMS is less likely to be guided straight into that lock (deep-review).
  const ResendPolicy({this.cooldown = const Duration(seconds: 180)});

  final Duration cooldown;

  /// Whole seconds remaining before a resend is allowed (0 once elapsed).
  int secondsRemaining(DateTime sentAt, DateTime now) {
    final remaining = cooldown - now.difference(sentAt);
    return remaining > Duration.zero ? remaining.inSeconds : 0;
  }

  bool canResend(DateTime sentAt, DateTime now) =>
      secondsRemaining(sentAt, now) == 0;

  /// `m:ss` for display, e.g. 42 → "0:42".
  String format(int seconds) {
    final m = seconds ~/ 60;
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
