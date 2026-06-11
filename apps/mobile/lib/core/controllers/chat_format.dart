// Pure chat presentation formatting — conversation-list timestamps, in-thread day labels,
// and avatar initials. No Flutter, no IO → unit-testable (CLAUDE.md: logic in controllers).
//
// The chat design uses ABSOLUTE time buckets ("14:06", "เมื่อวาน", "2 มิ.ย."), unlike the
// notification list's compact relative times — so this is separate from [RelativeTime]
// (which stays untouched for notifications). Day comparisons use the LOCAL calendar day of
// both operands (`.toLocal()`), matching what the user's clock shows.

/// Bilingual absolute-time buckets + initials for the chat flow. Pick the language at the
/// call site (the locale toggle drives it).
class ChatFormat {
  const ChatFormat._();

  static const List<String> _thMonths = [
    'ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.',
    'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.',
  ];
  static const List<String> _enMonths = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  /// Whole local-calendar-days between [now] and [when] (0 = same day, 1 = yesterday).
  /// Date-only values are rebuilt in UTC so the difference is DST-safe.
  static int _daysAgo(DateTime when, DateTime now) {
    final w = when.toLocal();
    final n = now.toLocal();
    return DateTime.utc(n.year, n.month, n.day)
        .difference(DateTime.utc(w.year, w.month, w.day))
        .inDays;
  }

  /// `true` when both instants fall on the same LOCAL calendar day.
  static bool sameLocalDay(DateTime a, DateTime b) => _daysAgo(a, b) == 0;

  static String _hm(DateTime local) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.hour)}:${two(local.minute)}';
  }

  /// Short date, design-style: "2 มิ.ย." / "2 Jun".
  static String shortDate(DateTime when, {required bool thai}) {
    final w = when.toLocal();
    return '${w.day} ${(thai ? _thMonths : _enMonths)[w.month - 1]}';
  }

  /// Conversation-list timestamp (design buckets): same local day → "14:06";
  /// previous local day → "เมื่อวาน" / "Yesterday"; older → "2 มิ.ย." / "2 Jun".
  /// Future/clock-skew clamps to the clock time (same-day branch).
  static String listTime(DateTime when, {required DateTime now, required bool thai}) {
    final days = _daysAgo(when, now);
    if (days <= 0) return _hm(when.toLocal());
    if (days == 1) return thai ? 'เมื่อวาน' : 'Yesterday';
    return shortDate(when, thai: thai);
  }

  /// In-thread day-separator label: "วันนี้" / "Today", "เมื่อวาน" / "Yesterday",
  /// else the short date ("2 มิ.ย." / "2 Jun").
  static String dayLabel(DateTime when, {required DateTime now, required bool thai}) {
    final days = _daysAgo(when, now);
    if (days <= 0) return thai ? 'วันนี้' : 'Today';
    if (days == 1) return thai ? 'เมื่อวาน' : 'Yesterday';
    return shortDate(when, thai: thai);
  }

  /// Initials for an avatar tile (e.g. "Somchai P." → "SP"); single word → first two
  /// characters; null/blank → "?". Shared by the list tile, bubble avatar and thread header.
  static String initials(String? name) {
    final n = (name ?? '').trim();
    if (n.isEmpty) return '?';
    final parts = n.split(RegExp(r'\s+'));
    if (parts.length >= 2 && parts[1].isNotEmpty) {
      return (parts[0][0] + parts[1][0]).toUpperCase();
    }
    return n.substring(0, n.length >= 2 ? 2 : 1).toUpperCase();
  }
}
