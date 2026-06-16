import 'package:flutter/material.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../../core/models/booking.dart';
import '../../../core/models/money.dart';

/// A guard-facing booking card: place/time/hours + computed fee, with an optional [actions] row
/// (accept/decline) or [onTap] (open active job). Used on the dashboard, jobs list, and detail.
class GuardJobCard extends StatelessWidget {
  const GuardJobCard({
    super.key,
    required this.booking,
    required this.isThai,
    this.onTap,
    this.actions,
    this.highlight = false,
  });

  final Booking booking;
  final bool isThai;
  final VoidCallback? onTap;
  final Widget? actions;
  final bool highlight;

  /// Booking fee = base_fee × hours × guard_count (server-owned base_fee, in satang).
  int get _feeSatang =>
      Money.satangFromString(booking.baseFee) *
      (booking.hours ?? 0) *
      (booking.guardCount ?? 1);

  static String _two(int n) => n.toString().padLeft(2, '0');

  String get _timeWindow {
    final start = booking.scheduledAt?.toLocal();
    final hours = booking.hours ?? 0;
    final unit = isThai ? 'ชม.' : 'hrs';
    if (start == null) return '$hours $unit';
    final end = start.add(Duration(hours: hours));
    return '${_two(start.hour)}:${_two(start.minute)}–${_two(end.hour)}:${_two(end.minute)} · $hours $unit';
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      // Design pending card: pale amber-50 wash, not a saturated amber block.
      color: highlight ? PgTokens.colorWarningBg : PgTokens.colorSurface,
      borderRadius: BorderRadius.circular(PgTokens.radius2xl),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(PgTokens.radius2xl),
        child: Container(
          padding: const EdgeInsets.all(PgTokens.space4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(PgTokens.radius2xl),
            // Design's soft amber-300 border (exact token since the full-ramp regen).
            border: Border.all(
                color: highlight
                    ? PgTokens.colorAmber300
                    : PgTokens.colorBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          booking.address ??
                              (isThai ? 'งานรักษาความปลอดภัย' : 'Security job'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 15.5, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Text(_timeWindow,
                            style: const TextStyle(
                                fontSize: 12.5,
                                color: PgTokens.colorTextMuted)),
                      ],
                    ),
                  ),
                  const SizedBox(width: PgTokens.space2),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Design fee: 17/600 in the mono numeric face.
                      Text(Money.format(_feeSatang),
                          style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'IBMPlexMono',
                              fontFeatures: [FontFeature.tabularFigures()])),
                      Text(
                          isThai
                              ? '${booking.guardCount ?? 1} คน'
                              : '${booking.guardCount ?? 1} guard'
                                  '${(booking.guardCount ?? 1) > 1 ? 's' : ''}',
                          style: const TextStyle(
                              fontSize: 11, color: PgTokens.colorTextFaint)),
                    ],
                  ),
                ],
              ),
              if (actions != null) ...[
                const SizedBox(height: PgTokens.space3),
                actions!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
