// Pure relative-time formatting for notification timestamps. No Flutter, no IO → unit-testable.
//
// Compares in UTC (both operands normalised) to avoid v1's timezone bug, and renders the
// compact Thai/English forms the design uses ("2 นาที" / "2m", "เมื่อวาน"-style buckets).

/// Bilingual relative time. Pick the language at the call site (the locale toggle drives it).
class RelativeTime {
  const RelativeTime._();

  /// Thai compact form (e.g. "เมื่อสักครู่", "5 นาที", "3 ชม.", "2 วัน", "4 สัปดาห์").
  static String th(DateTime when, {required DateTime now}) =>
      _format(when, now, thai: true);

  /// English compact form (e.g. "just now", "5m", "3h", "2d", "4w").
  static String en(DateTime when, {required DateTime now}) =>
      _format(when, now, thai: false);

  static String _format(DateTime when, DateTime now, {required bool thai}) {
    final diff = now.toUtc().difference(when.toUtc());
    // Future or clock-skew → treat as "just now".
    final secs = diff.inSeconds < 0 ? 0 : diff.inSeconds;
    if (secs < 60) return thai ? 'เมื่อสักครู่' : 'just now';
    final mins = secs ~/ 60;
    if (mins < 60) return thai ? '$mins นาที' : '${mins}m';
    final hours = mins ~/ 60;
    if (hours < 24) return thai ? '$hours ชม.' : '${hours}h';
    final days = hours ~/ 24;
    if (days < 7) return thai ? '$days วัน' : '${days}d';
    final weeks = days ~/ 7;
    return thai ? '$weeks สัปดาห์' : '${weeks}w';
  }
}
