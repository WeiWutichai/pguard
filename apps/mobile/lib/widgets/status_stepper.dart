import 'package:flutter/material.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../core/models/booking.dart';

/// Horizontal lifecycle stepper for the live booking-status screen (per the Active-Standby
/// design's slot indicator): done = success green, current = amber, pending = sunken, and a
/// negative terminal (declined/cancelled) paints the whole bar red. Below it, the current
/// status label (TH · EN). Pure presentation — it just renders [status].
class BookingStatusStepper extends StatelessWidget {
  const BookingStatusStepper({super.key, required this.status});

  final BookingStatus status;

  @override
  Widget build(BuildContext context) {
    const steps = BookingLifecycle.steps;
    final current = BookingLifecycle.stepIndex(status);
    final negative = BookingLifecycle.isNegativeTerminal(status);
    final completed = status == BookingStatus.completed;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (var i = 0; i < steps.length; i++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2.5),
                  child: Container(
                    height: 6,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(3),
                      color: _segmentColor(i, current,
                          negative: negative, completed: completed),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: PgTokens.space2),
        Row(
          children: [
            Icon(_icon(negative: negative, completed: completed),
                size: 16, color: _accent(negative)),
            const SizedBox(width: PgTokens.space1),
            Flexible(
              child: Text(
                '${BookingLifecycle.labelTh(status)} · ${BookingLifecycle.labelEn(status)}',
                style: const TextStyle(
                    fontSize: 12.5, color: PgTokens.colorTextMuted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ],
    );
  }

  static Color _segmentColor(int i, int current,
      {required bool negative, required bool completed}) {
    if (negative) return PgTokens.colorDanger;
    if (completed) return PgTokens.colorSuccess;
    if (i < current) return PgTokens.colorSuccess;
    if (i == current) return PgTokens.colorWarning;
    return PgTokens.colorSunken;
  }

  static IconData _icon({required bool negative, required bool completed}) {
    if (negative) return Icons.cancel_outlined;
    if (completed) return Icons.check_circle_outline;
    return Icons.timelapse_outlined;
  }

  static Color _accent(bool negative) =>
      negative ? PgTokens.colorDanger : PgTokens.colorSuccess;
}
