import 'package:flutter/material.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../core/models/booking.dart';

/// A small COLOURED status pill for a booking's lifecycle status (#127) — a tinted rounded chip with
/// a status dot + the bilingual status label, so a booking's current state stands out instead of
/// reading as flat text. Status-driven palette:
///   • `pending_completion` (the guard's job awaiting the customer's confirmation) → AMBER/warning —
///     the case #127 most needs to emphasise (it otherwise looked ignorable);
///   • `completed` → GREEN/success;
///   • `declined` / `cancelled` (negative terminals) → DANGER red;
///   • `requested` → muted (still finding a guard);
///   • everything in flight (accepted / en_route / arrived) → INFO blue.
///
/// SHARED so the same pill renders wherever a status is shown (the booking-details sheet today; the
/// guard jobs list / customer lists can reuse it next), keeping the colour mapping in ONE place.
/// Pure presentation — no controllers, no I/O.
class BookingStatusPill extends StatelessWidget {
  const BookingStatusPill({
    super.key,
    required this.status,
    required this.isThai,
  });

  final BookingStatus status;
  final bool isThai;

  /// (foreground, background) palette for [status]. Foreground tints the dot + the label; the
  /// background is the soft chip fill. All from the design tokens (no raw colours).
  static (Color fg, Color bg) _palette(BookingStatus status) {
    switch (status) {
      case BookingStatus.pendingCompletion:
        return (PgTokens.colorAmber700, PgTokens.colorAmber50);
      case BookingStatus.completed:
        return (PgTokens.colorSuccess, PgTokens.colorSuccessBg);
      case BookingStatus.declined:
      case BookingStatus.cancelled:
        return (PgTokens.colorDanger, PgTokens.colorDangerBg);
      case BookingStatus.requested:
        return (PgTokens.colorTextMuted, PgTokens.colorSunken);
      case BookingStatus.accepted:
      case BookingStatus.enRoute:
      case BookingStatus.arrived:
        return (PgTokens.colorInfo, PgTokens.colorInfoBg);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = _palette(status);
    final label = isThai
        ? BookingLifecycle.labelTh(status)
        : BookingLifecycle.labelEn(status);
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(PgTokens.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
