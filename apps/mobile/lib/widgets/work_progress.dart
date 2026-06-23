import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../core/controllers/guard_clock.dart';

/// Shared work-progress visuals from the hi-fi guard/customer mockups: the 74px countdown ring
/// + a per-hour check-in timeline row. Built so both the customer live-status screen and the
/// guard active-job working panel can render the same components (the guard panel uses them now;
/// migrating live_status onto these is a follow-up).

/// The 74px circular countdown ("HH:MM" + "เหลือ/left") beside the booked range, elapsed line and
/// a 7px progress bar. Pure [WorkClock] math; a 1s display tick re-reads it (display only, not
/// status polling).
class WorkCountdownRing extends StatelessWidget {
  const WorkCountdownRing(
      {super.key, required this.clock, required this.isThai});

  final WorkClock clock;
  final bool isThai;

  static String _two(int n) => n.toString().padLeft(2, '0');
  static String _hm(DateTime when) {
    final l = when.toLocal();
    return '${_two(l.hour)}:${_two(l.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: Stream<int>.periodic(const Duration(seconds: 1), (i) => i),
      builder: (context, _) {
        final now = DateTime.now().toUtc();
        final remaining = clock.remaining(now);
        final elapsed = clock.elapsed(now);
        final endsAt = clock.startedAt.add(clock.total);
        return Row(
          children: [
            SizedBox(
              width: 74,
              height: 74,
              child: CustomPaint(
                painter: _CountdownRingPainter(progress: clock.progress(now)),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${_two(remaining.inHours)}:${_two(remaining.inMinutes % 60)}',
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: PgTokens.colorText),
                      ),
                      Text(isThai ? 'เหลือ' : 'left',
                          style: const TextStyle(
                              fontSize: 10.5, color: PgTokens.colorTextMuted)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: PgTokens.space4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isThai
                        ? '${_hm(clock.startedAt)} – ${_hm(endsAt)} น.'
                        : '${_hm(clock.startedAt)} – ${_hm(endsAt)}',
                    style: const TextStyle(
                        fontSize: 12.5, color: PgTokens.colorTextMuted),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isThai
                        ? 'ผ่านไป ${elapsed.inHours} ชม. ${elapsed.inMinutes % 60} นาที'
                        : '${elapsed.inHours}h ${elapsed.inMinutes % 60}m worked',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: PgTokens.space2),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: SizedBox(
                      height: 7,
                      child: Stack(
                        children: [
                          Container(color: PgTokens.colorSunken),
                          FractionallySizedBox(
                            widthFactor: clock.progress(now).clamp(0.0, 1.0),
                            child: Container(color: PgTokens.colorPrimary),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// One vertical-timeline row (the mockup's hourly check-in node): a 30px node (done = brand fill
/// + white check; current = 2px brand ring + number; pending = grey ring), the [time] + [title],
/// and an optional [statusLabel] pill on the right (tone by [done]/[isCurrent]).
class CheckInTimelineRow extends StatelessWidget {
  const CheckInTimelineRow({
    super.key,
    required this.index,
    required this.title,
    required this.done,
    required this.isCurrent,
    required this.isLast,
    this.time,
    this.statusLabel,
    this.onTap,
  });

  /// 1-based node number shown when not done.
  final int index;
  final String title;
  final bool done;
  final bool isCurrent;
  final bool isLast;
  final String? time;
  final String? statusLabel;

  /// When non-null the whole row is tappable (e.g. a reported check-in opens its photo); the
  /// status pill then carries a small photo glyph so it reads as actionable.
  final VoidCallback? onTap;

  Widget _node() {
    if (done) {
      return Container(
        width: 34,
        height: 34,
        decoration: const BoxDecoration(
            color: PgTokens.colorPrimary, shape: BoxShape.circle),
        child: const Icon(Icons.check, size: 15, color: Colors.white),
      );
    }
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: isCurrent ? PgTokens.colorPrimary : PgTokens.colorBorder,
          width: 2,
        ),
      ),
      child: Text('$index',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: isCurrent ? PgTokens.colorPrimary : PgTokens.colorTextMuted,
          )),
    );
  }

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color fg) = done
        ? (PgTokens.colorSuccessBg, PgTokens.colorSuccess)
        : isCurrent
            ? (PgTokens.colorWarningBg, PgTokens.colorWarning)
            : (PgTokens.colorSunken, PgTokens.colorTextMuted);
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            _node(),
            if (!isLast)
              Container(
                width: 2,
                height: 22,
                color: done ? PgTokens.colorPrimary : PgTokens.colorBorder,
              ),
          ],
        ),
        const SizedBox(width: PgTokens.space3),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                if (time != null) ...[
                  Text(time!,
                      style: const TextStyle(
                          fontSize: 12.5, color: PgTokens.colorTextMuted)),
                  const SizedBox(width: PgTokens.space2),
                ],
                Expanded(
                  child: Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                ),
                if (statusLabel != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                    decoration: BoxDecoration(
                        color: bg,
                        borderRadius:
                            BorderRadius.circular(PgTokens.radiusFull)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (onTap != null) ...[
                          Icon(Icons.photo_outlined, size: 13, color: fg),
                          const SizedBox(width: 5),
                        ],
                        Text(statusLabel!,
                            style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: fg)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
    if (onTap == null) return row;
    return InkWell(
      borderRadius: BorderRadius.circular(PgTokens.radiusLg),
      onTap: onTap,
      child: row,
    );
  }
}

/// The 74px countdown ring: full track in border grey, the progressed arc in brand with a round
/// cap, starting at 12 o'clock.
class _CountdownRingPainter extends CustomPainter {
  const _CountdownRingPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 6.0;
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - stroke) / 2;
    final track = Paint()
      ..color = PgTokens.colorBorder
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawCircle(center, radius, track);
    final arc = Paint()
      ..color = PgTokens.colorPrimary
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress.clamp(0.0, 1.0),
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(covariant _CountdownRingPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
