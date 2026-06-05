/// PURE OTP resend-cooldown logic — deadline based, no timers, fully unit-testable. The OTP
/// screen drives a 1-second display ticker; this computes what to show. (This is a UI
/// countdown, NOT the booking-status path — that is WebSocket push with zero polling.)
class ResendPolicy {
  const ResendPolicy({this.cooldown = const Duration(seconds: 60)});

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
