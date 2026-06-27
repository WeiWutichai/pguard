import 'package:flutter/material.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../core/models/booking.dart';

/// SHARED vertical status timeline of the guard's progress for ONE booking — used by BOTH the
/// customer live-status screen and the guard active-job screen (#123). It walks the booking
/// lifecycle (accept → en route → arrived → working → completed) and renders one step per stage:
/// reached steps are TICKED (brand fill + check), the current step is HIGHLIGHTED (amber ring),
/// and steps not yet reached are pending (grey ring). Purely status-driven — no timer/polling.
///
/// STEP ↔ STATUS mapping (the customer-facing happy path, matching `BookingLifecycle.steps` plus a
/// distinct "Working" step the customer doesn't otherwise see — the booking stays `arrived` while
/// the guard works, so "Working" is derived from `arrived` + the job having started):
///   • Accepted          ← booking has reached `accepted`
///   • En route          ← booking has reached `en_route`
///   • Arrived           ← booking has reached `arrived`
///   • Working           ← the guard has started work ([started] true) while at the site, or the
///                         booking has moved past `arrived` (pending_completion/completed)
///   • Completed         ← booking has reached `completed`
///
/// TIMESTAMPS: the booking API exposes NO per-transition timestamps (only `created_at`,
/// `updated_at`, `paid_at`, and the server-internal `work_started_at` — none surfaced per step), so
/// this timeline shows the steps with the current one highlighted but does NOT print an exact time
/// against each transition. To show real per-step times (e.g. "accepted 14:02 · arrived 14:48") the
/// backend must expose per-transition timestamps — see the FLAG in the task report.
///
/// A NEGATIVE-TERMINAL booking (declined/cancelled) collapses to a single red "cancelled" row
/// rather than a half-ticked happy path (the job will not proceed).
class BookingStatusTimeline extends StatelessWidget {
  const BookingStatusTimeline({
    super.key,
    required this.status,
    required this.isThai,
    this.started = false,
  });

  /// The booking's current lifecycle status.
  final BookingStatus status;

  /// TH (true) vs EN (false) step labels.
  final bool isThai;

  /// Whether the guard has STARTED work at the site. Lets the "Working" step tick the instant the
  /// guard taps "Start job" (the booking stays `arrived`, so status alone can't tell working from
  /// just-arrived). The customer screen, which has no client start stamp, passes the default
  /// (false) — "Working" then ticks only once the booking moves past `arrived`.
  final bool started;

  /// The ordered steps this timeline renders. Mirrors the customer happy path but inserts a
  /// distinct "Working" step (derived, not a wire status) between arrived and completed.
  static const List<_TimelineStep> _steps = [
    _TimelineStep(BookingStatus.accepted, 'เริ่มรับงาน', 'Accepted'),
    _TimelineStep(BookingStatus.enRoute, 'กำลังเดินทาง', 'En route'),
    _TimelineStep(BookingStatus.arrived, 'ถึงจุดนัด', 'Arrived'),
    // Label is "กำลังปฏิบัติงาน / Working" (the on-duty STATE) — deliberately NOT "เริ่มงาน"
    // (which is the guard's "Start job" CTA on the active-job screen; using it here would collide
    // with that button both visually and in widget tests).
    _TimelineStep(_workingMarker, 'กำลังปฏิบัติงาน', 'Working'),
    _TimelineStep(BookingStatus.completed, 'เสร็จงาน', 'Completed'),
  ];

  /// Sentinel for the derived "Working" step (no such wire status — the booking stays `arrived`).
  static const BookingStatus _workingMarker = BookingStatus.pendingCompletion;

  /// 0-based index of the CURRENT step for [status] (+[started]); the step the guard is on now.
  /// Returns -1 before any step is reached (`requested`).
  int get _currentIndex {
    switch (status) {
      case BookingStatus.requested:
        return -1;
      case BookingStatus.accepted:
        return 0;
      case BookingStatus.enRoute:
        return 1;
      case BookingStatus.arrived:
        // Arrived-but-not-started sits on "Arrived"; once work has started it advances to "Working".
        return started ? 3 : 2;
      case BookingStatus.pendingCompletion:
        // The guard finished working and requested completion — "Working" is the live step until
        // the customer approves.
        return 3;
      case BookingStatus.completed:
        return 4;
      case BookingStatus.declined:
      case BookingStatus.cancelled:
        return -1; // handled by the negative-terminal branch
    }
  }

  @override
  Widget build(BuildContext context) {
    // A job that will not proceed: one calm red row, never a half-ticked happy path.
    if (BookingLifecycle.isNegativeTerminal(status)) {
      return _TerminalRow(
        label: isThai
            ? '${BookingLifecycle.labelTh(status)} · ${BookingLifecycle.labelEn(status)}'
            : BookingLifecycle.labelEn(status),
      );
    }

    final current = _currentIndex;
    final completed = status == BookingStatus.completed;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < _steps.length; i++)
          _StepRow(
            label: isThai ? _steps[i].th : _steps[i].en,
            // A step is DONE when the current step is past it, or the whole job is completed.
            done: completed || i < current,
            isCurrent: !completed && i == current,
            isLast: i == _steps.length - 1,
          ),
      ],
    );
  }
}

/// One step in the shared timeline (label pair + the wire status it maps to, where applicable).
class _TimelineStep {
  const _TimelineStep(this.status, this.th, this.en);

  final BookingStatus status;
  final String th;
  final String en;
}

/// One vertical row: a 28px node (done = brand fill + white check; current = 2px amber ring + dot;
/// pending = grey ring) joined to the next row by a 22px rail (brand when the step above is done),
/// with the step label to the right.
class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.label,
    required this.done,
    required this.isCurrent,
    required this.isLast,
  });

  final String label;
  final bool done;
  final bool isCurrent;
  final bool isLast;

  Widget _node() {
    if (done) {
      return Container(
        width: 28,
        height: 28,
        decoration: const BoxDecoration(
            color: PgTokens.colorPrimary, shape: BoxShape.circle),
        child: const Icon(Icons.check, size: 15, color: Colors.white),
      );
    }
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isCurrent ? PgTokens.colorWarningBg : null,
        border: Border.all(
          color: isCurrent ? PgTokens.colorWarning : PgTokens.colorBorder,
          width: 2,
        ),
      ),
      child: isCurrent
          ? Container(
              width: 9,
              height: 9,
              decoration: const BoxDecoration(
                  color: PgTokens.colorWarning, shape: BoxShape.circle),
            )
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final Color labelColor = done
        ? PgTokens.colorText
        : isCurrent
            ? PgTokens.colorText
            : PgTokens.colorTextMuted;
    return Row(
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
            padding: const EdgeInsets.only(top: 5),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w600,
                color: labelColor,
              ),
            ),
          ),
        ),
        if (isCurrent)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                  color: PgTokens.colorWarning, shape: BoxShape.circle),
            ),
          ),
      ],
    );
  }
}

/// The single red row a negative-terminal (declined/cancelled) booking collapses to.
class _TerminalRow extends StatelessWidget {
  const _TerminalRow({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: const BoxDecoration(
              color: PgTokens.colorDanger, shape: BoxShape.circle),
          child: const Icon(Icons.close, size: 15, color: Colors.white),
        ),
        const SizedBox(width: PgTokens.space3),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: PgTokens.colorDanger),
          ),
        ),
      ],
    );
  }
}
