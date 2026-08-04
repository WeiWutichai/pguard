/// The ONE canonical mapping between the server's stable cancellation/decline reason CODES and
/// their bilingual labels.
///
/// What travels on the wire (and lands in `booking.bookings.cancellation_reason`, the
/// `booking.cancelled` / `booking.declined` events, and web-admin reporting) is ALWAYS the CODE —
/// never localized text. That is what makes the same booking read correctly in Thai and English
/// and lets admin group/report on it.
///
/// Contract:
///  - `PUT /v1/bookings/{id}/cancel`  `{ reason: <customer code>, note?: string(<=500) }`
///  - `PUT /v1/bookings/{id}/decline` `{ reason: <guard code>,    note?: string(<=500) }`
///  - `reason` is REQUIRED (400 `CANCEL_REASON_REQUIRED`);
///  - `other` REQUIRES a non-blank note (400 `CANCEL_NOTE_REQUIRED`).
///
/// Both the CAPTURE side (customer cancellation screen, guard withdraw screen) and the DISPLAY
/// side (live status, payment, active job, notification tiles) go through [labelFor] — no screen
/// re-declares a label string, so the two sides can never drift.
class PgCancelReason {
  const PgCancelReason._();

  // ---- Customer codes (PUT /bookings/{id}/cancel) -------------------------------------------
  static const String changedPlan = 'changed_plan';
  static const String mistake = 'mistake';
  static const String notNeeded = 'not_needed';

  // ---- Guard codes (PUT /bookings/{id}/decline) ---------------------------------------------
  static const String emergency = 'emergency';
  static const String sick = 'sick';
  static const String cannotReach = 'cannot_reach';

  /// Valid on BOTH endpoints — and the only code that requires a note ([requiresNote]).
  static const String other = 'other';

  /// The customer's reason options, in the order the cancellation screen renders them
  /// (index 0 is pre-selected, matching the design's default).
  static const List<String> customer = [changedPlan, mistake, notNeeded, other];

  /// The guard's reason options, in the order the withdraw screen renders them.
  static const List<String> guard = [emergency, sick, cannotReach, other];

  /// Server-enforced cap on the free-text note (counted in CHARACTERS — Thai text is multi-byte,
  /// so the server counts `chars()`, not bytes; `maxLength` on a TextField matches that).
  static const int maxNoteLength = 500;

  static const Map<String, String> _th = {
    changedPlan: 'เปลี่ยนแผน',
    mistake: 'แจ้งผิดพลาด',
    notNeeded: 'ไม่ต้องการแล้ว',
    emergency: 'เหตุฉุกเฉินส่วนตัว',
    sick: 'ป่วย',
    cannotReach: 'เดินทางไปไม่ได้',
    other: 'อื่นๆ',
  };

  static const Map<String, String> _en = {
    changedPlan: 'Changed plans',
    mistake: 'Booked by mistake',
    notNeeded: 'No longer needed',
    emergency: 'Personal emergency',
    sick: 'Sick',
    cannotReach: "Can't reach site",
    other: 'Other',
  };

  /// The human label for [code] in the active language.
  ///
  /// Returns `''` for a null/blank code (pre-migration bookings have no reason — the caller
  /// simply renders nothing), and the RAW code for an unknown one: forward-compatible, so a code
  /// this build predates still shows *something* rather than silently vanishing or being
  /// mislabelled as "other".
  static String labelFor(String? code, bool isThai) {
    final c = code?.trim();
    if (c == null || c.isEmpty) return '';
    return (isThai ? _th : _en)[c] ?? c;
  }

  /// Whether picking [code] obliges the user to type a note (the server 400s
  /// `CANCEL_NOTE_REQUIRED` on a blank note for `other`).
  static bool requiresNote(String code) => code == other;

  /// Normalize a typed note for the wire: trimmed, and `null` when blank (the server trims and
  /// stores `None` for an empty note — sending `""` would only add noise).
  static String? normalizeNote(String raw) {
    final note = raw.trim();
    return note.isEmpty ? null : note;
  }

  // ---- Note-field copy (shared by both capture screens so the wording can't drift) -----------

  /// Field label above the free-text note; flips to "(required)" for `other`.
  static String noteLabel(bool isThai, {required bool required}) => isThai
      ? (required ? 'รายละเอียด (จำเป็น)' : 'รายละเอียดเพิ่มเติม (ไม่บังคับ)')
      : (required ? 'Details (required)' : 'Details (optional)');

  /// Placeholder for the note field.
  static String noteHint(bool isThai, {required bool required}) => isThai
      ? (required ? 'โปรดระบุเหตุผล…' : 'บอกเราเพิ่มเติม…')
      : (required ? 'Tell us the reason…' : 'Add more detail…');

  /// Inline message shown when the user submits `other` with a blank note — the LOCAL twin of the
  /// server's 400 `CANCEL_NOTE_REQUIRED` (see api_error_l10n.dart), so the user is stopped here
  /// instead of after a round-trip.
  static String noteMissingMessage(bool isThai) => isThai
      ? 'กรุณาระบุรายละเอียดเมื่อเลือก "อื่นๆ"'
      : 'Please add a note when the reason is "Other"';
}
