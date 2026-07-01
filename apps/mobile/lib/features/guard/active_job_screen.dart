import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../core/controllers/active_job_controller.dart';
import '../../core/controllers/booking_status_controller.dart';
import '../../core/controllers/chat_launcher.dart';
import '../../core/controllers/guard_jobs_controller.dart';
import '../../core/controllers/guard_route_controller.dart';
import '../../core/controllers/locale_controller.dart';
import '../../core/controllers/progress_reports_controller.dart';
import '../../core/controllers/session_controller.dart';
import '../../core/controllers/tracking_controller.dart';
import '../../core/models/booking.dart';
import '../../core/models/chat.dart';
import '../../core/models/geo.dart';
import '../../core/models/progress_report.dart';
import '../../core/network/api_exception.dart';
import '../../widgets/booking_status_timeline.dart';
import '../../widgets/pg_error_state.dart';
import '../../widgets/pguard_header.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/progress_report_viewer.dart';
import '../../widgets/status_stepper.dart';
import '../../widgets/work_progress.dart';
import '../booking/live_status_screen.dart' show showBookingDetailsSheet;
import '../booking/widgets/job_receipt_sheet.dart';
import '../booking/widgets/travel_map_preview.dart';
import '../call/widgets/call_entry_button.dart';
import '../chat/chat_routes.dart';
import '../chat/widgets/chat_entry_button.dart';
import 'guard_navigation_screen.dart';
import 'widgets/check_in_sheet.dart';

/// The active-job working screen: drives the lifecycle transitions (en-route → arrived → start
/// → complete), shows a DISPLAY-only countdown (from the client-recorded start time, since the
/// API doesn't expose work_started_at), and prompts the hourly photo+GPS check-in. Status flows
/// to the customer over the existing WS — nothing is polled here. Per `Mobile Guard.html`.
class ActiveJobScreen extends ConsumerStatefulWidget {
  const ActiveJobScreen({super.key, required this.bookingId});

  final String bookingId;

  @override
  ConsumerState<ActiveJobScreen> createState() => _ActiveJobScreenState();
}

class _ActiveJobScreenState extends ConsumerState<ActiveJobScreen>
    with WidgetsBindingObserver {
  /// True while THIS screen holds a presence job-streaming lease for the booking, so we release
  /// exactly the one we took (and only once) on dispose.
  bool _leaseHeld = false;

  /// The keepAlive tracking notifier, captured in [initState]. Cached so [dispose] can release the
  /// lease WITHOUT touching `ref` (which is illegal once the widget is disposed). The instance is
  /// stable for the app lifetime (keepAlive), so caching it is safe.
  late final TrackingController _tracking =
      ref.read(trackingControllerProvider.notifier);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Stream LIVE GPS to presence for the whole active-job window (independent of the manual
    // online toggle) so the customer's map shows the guard moving. Driven by the job status:
    // `listenManual` (fireImmediately) syncs the lease on first resolve and on every status change,
    // OUTSIDE the build phase (safe to mutate the keepAlive TrackingController).
    ref.listenManual(
      activeJobControllerProvider(widget.bookingId),
      (_, next) => _syncStreamingLease(next.valueOrNull?.booking.status),
      fireImmediately: true,
    );
    // Live cancellation: the active-job controller has no WS of its own (it re-fetches only on
    // resume), so subscribe to the booking-status feed and fold a terminal transition the guard
    // didn't drive — chiefly the CUSTOMER cancelling — into the active-job state the instant it
    // lands. Without this a cancelled job would keep showing its working chrome until the guard
    // backgrounded + resumed. The fold is idempotent (a no-op when the status already matches).
    ref.listenManual(
      bookingStatusControllerProvider(widget.bookingId),
      (_, next) {
        final status = next.valueOrNull?.status;
        if (status != null && BookingLifecycle.isTerminal(status)) {
          ref
              .read(activeJobControllerProvider(widget.bookingId).notifier)
              .applyExternalStatus(status);
        }
      },
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Drop the GPS job-streaming lease on the way out via the CACHED notifier (ref is unusable in
    // dispose). A manual-online guard keeps streaming (the toggle still holds the feed); a standby
    // guard's feed tears down when the last lease goes.
    if (_leaseHeld) {
      _tracking.stopJobStreaming(widget.bookingId);
    }
    super.dispose();
  }

  /// Take or release the GPS streaming lease so the guard streams LIVE position to presence for the
  /// JOURNEY window (en_route/arrived/pending_completion) regardless of the manual "พร้อมรับงาน"
  /// toggle — this is what keeps the customer's live map fresh. DEFERRED until the guard is actually
  /// on the way: a merely-`accepted` job does NOT take the lease, so a standby guard who only opens
  /// the job to view it is not hit with the OS location-permission dialog (taking the lease is what
  /// requests location). The instant the job leaves the streaming window (completed/cancelled/
  /// declined, or back before en_route) we release it.
  void _syncStreamingLease(BookingStatus? status) {
    final wantLease = status != null && BookingLifecycle.isStreaming(status);
    if (wantLease == _leaseHeld) return;
    if (wantLease) {
      _tracking.startJobStreaming(widget.bookingId);
    } else {
      _tracking.stopJobStreaming(widget.bookingId);
    }
    _leaseHeld = wantLease;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    // Belt-and-suspenders for a MISSED payment push (foreground push handling can be skipped while
    // backgrounded): re-fetch the guard's active job on resume so a `paid_at` that landed while the
    // app was away un-gates "Go en route". This is a one-shot fetch on an event (resume), NOT a
    // Timer.periodic — the active-job controller has no live WS, so a manual re-pull is the only way
    // it reflects an async server change.
    if (lifecycle == AppLifecycleState.resumed) {
      // SKIP the re-fetch while a check-in is in flight: capturing the checkpoint photo opens the
      // system camera, which backgrounds the app — so this `resumed` fires when the camera RETURNS,
      // mid-check-in. Invalidating then drops the controller into `loading` (wiping the
      // client-only `startedAt` + the in-memory completedCheckIns) and races the not-yet-submitted
      // report, which is exactly what made round 1 look unregistered / re-prompt "Start job". The
      // payment-resync this guard exists for can wait until the check-in sheet closes.
      if (ref.read(workSessionStoreProvider).isCheckInInFlight(widget.bookingId)) {
        return;
      }
      ref.invalidate(activeJobControllerProvider(widget.bookingId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bookingId = widget.bookingId;
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    final async = ref.watch(activeJobControllerProvider(bookingId));
    final state = async.valueOrNull;
    final booking = state?.booking;
    final stage = state == null ? null : stageOf(state);
    final header = _headerFor(stage, isThai, status: booking?.status);
    final myUserId = ref.watch(sessionProvider).user?.userId;

    return Scaffold(
      backgroundColor: PgTokens.colorBg,
      appBar: PGuardHeader(
        title: header.title,
        subtitle: header.subtitle,
        showBack: true,
        // FROZEN-BACK GUARD: the guard reaches this screen via `context.go('/guard/active/{id}')`
        // (job-detail accept), which REPLACES the stack — so the default header back (`maybePop`)
        // had nothing to pop and silently did nothing, stranding the guard on the live/terminal job
        // until they force-closed the app. Pop when there is a stack; otherwise return to the guard
        // home. (The in-body cancelled/awaiting/done bars keep their own explicit escapes too.)
        onBack: () =>
            context.canPop() ? context.pop() : context.go('/home/guard'),
        // Design: only the G4 Working header carries the LIVE indicator.
        live: stage == JobStage.working,
        background: header.background,
        // Guard ↔ customer call + chat for this job.
        trailing: booking == null
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CallEntryButton(
                    bookingId: booking.id,
                    // Callable window matches the calling service (accepted/en_route/arrived);
                    // pendingCompletion is active but NOT callable → would 409.
                    enabled: BookingLifecycle.isCallable(booking.status),
                  ),
                  const SizedBox(width: PgTokens.space2),
                  ChatEntryButton(
                    requestId: booking.id,
                    requestStatus: booking.status.wire,
                    acting: ChatRole.guard,
                    myUserId: myUserId,
                    counterpartUserId: booking.customerId,
                  ),
                ],
              ),
      ),
      body: SafeArea(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          // Shared hi-fi error state (Mobile - System.html) — retry re-fetches the job.
          error: (e, _) => PgErrorState(
            title: isThai ? 'โหลดงานไม่สำเร็จ' : 'Could not load this job',
            message: e is ApiException ? e.message : null,
            onRetry: () =>
                ref.invalidate(activeJobControllerProvider(bookingId)),
          ),
          data: (state) => _Body(bookingId: bookingId, state: state),
        ),
      ),
    );
  }
}

/// The lifecycle stage a guard acts on next.
enum JobStage { enRoute, arrived, start, working, awaiting, done }

JobStage stageOf(ActiveJobState s) {
  switch (s.booking.status) {
    case BookingStatus.accepted:
      return JobStage.enRoute;
    case BookingStatus.enRoute:
      return JobStage.arrived;
    case BookingStatus.arrived:
      return s.startedAt == null ? JobStage.start : JobStage.working;
    case BookingStatus.pendingCompletion:
      return JobStage.awaiting;
    default:
      return JobStage.done;
  }
}

/// Header (title, subtitle, background) for the current lifecycle stage, per the design's
/// per-state guard headers: G2 En route (blue), G3 Arrived (green-800), G4 Working (green-800),
/// G5 Awaiting customer (sand → amber-700, nearest token). The journey phase (accepted +
/// travelling) maps to G2; the at-location-not-started stage maps to G3. Falls back to the
/// generic active-job header while loading / after completion.
({String title, String subtitle, Color background}) _headerFor(
    JobStage? stage, bool isThai,
    {BookingStatus? status}) {
  // A negative terminal (the customer CANCELLED, or a decline) reads as cancelled — not the generic
  // "Active job" header — so the whole screen is unambiguous, matching the cancelled bottom bar.
  if (status != null && BookingLifecycle.isNegativeTerminal(status)) {
    return (
      title: isThai ? 'งานถูกยกเลิก' : 'Job cancelled',
      subtitle: isThai ? 'งานนี้ถูกยกเลิกแล้ว' : 'This job was cancelled',
      background: PgTokens.colorDanger,
    );
  }
  switch (stage) {
    case JobStage.enRoute:
    case JobStage.arrived:
      return (
        title: isThai ? 'กำลังเดินทาง' : 'En route',
        subtitle: isThai ? 'กำลังไปหาลูกค้า' : 'On the way',
        background: PgTokens.colorInfo, // nearest token to design #1F5FC2
      );
    case JobStage.start:
      return (
        title: isThai ? 'ถึงที่หมายแล้ว' : 'Arrived',
        subtitle: isThai ? 'ถึงจุดหมายแล้ว' : 'At the location',
        background: PgTokens.colorGreen800,
      );
    case JobStage.working:
      return (
        title: isThai ? 'งานกำลังดำเนินอยู่' : 'Working',
        subtitle: isThai ? 'กำลังปฏิบัติงาน' : 'Job in progress',
        background: PgTokens.colorGreen800,
      );
    case JobStage.awaiting:
      return (
        title: isThai ? 'รอลูกค้าตรวจสอบ' : 'Awaiting customer',
        subtitle: isThai ? 'รอการตรวจสอบ' : 'Awaiting review',
        background:
            PgTokens.colorAmber700, // nearest token to design sand #C26A1E
      );
    case JobStage.done:
    case null:
      return (
        title: isThai ? 'งานที่กำลังทำ' : 'Active job',
        subtitle: isThai ? 'งานปัจจุบัน' : 'Current job',
        background: PgTokens.colorGreen800,
      );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.bookingId, required this.state});

  final String bookingId;
  final ActiveJobState state;

  @override
  Widget build(BuildContext context) {
    final booking = state.booking;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(PgTokens.space4),
            // #123: the address card + status card + the shared status timeline can push the
            // working panel (countdown + check-in progress) just below the viewport on a short
            // device. A one-screen cache extent keeps that panel BUILT while just off-screen so its
            // countdown + progress are live the instant the guard scrolls. Cheap — the page has only
            // a handful of children.
            cacheExtent: 600,
            children: [
              // #126: while the guard waits on the CUSTOMER to confirm completion
              // (pending_completion), lead the screen with a prominent, emphasised status card so
              // the guard plainly understands they are BLOCKED on the customer — not stuck. Sits
              // above the address card so it is the first thing the guard reads on this stage.
              if (stageOf(state) == JobStage.awaiting) ...[
                const _AwaitingCustomerCard(),
                const SizedBox(height: PgTokens.space4),
              ],
              // #122: the address card carries an obvious "ดูรายละเอียดงาน / Job details" entry
              // that opens the SAME booking-details sheet the customer sees (address / place type /
              // schedule / hours / guards / payment / status / total), so the guard works from the
              // full job spec — folded into this card so it adds no extra height above the working
              // panel (a standalone block pushed the countdown out of the lazy ListView viewport).
              _AddressCard(booking: booking),
              const SizedBox(height: PgTokens.space4),
              Container(
                padding: const EdgeInsets.all(PgTokens.space4),
                decoration: BoxDecoration(
                  color: PgTokens.colorSurface,
                  borderRadius: BorderRadius.circular(PgTokens.radius2xl),
                  border: Border.all(color: PgTokens.colorBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    BookingStatusStepper(status: booking.status),
                    const Padding(
                      padding:
                          EdgeInsets.symmetric(vertical: PgTokens.space3),
                      child: Divider(height: 1, color: PgTokens.colorBorder),
                    ),
                    // #123: the SHARED guard-progress timeline (accept → en route → arrived →
                    // working → completed) — the SAME [BookingStatusTimeline] the customer's live
                    // screen renders. The guard side passes `started` from its client work-start
                    // stamp so the "Working" step ticks the instant the guard taps "Start job"
                    // (the booking stays `arrived` while working, so status alone can't tell them
                    // apart). Driven purely by status — no timer.
                    _GuardStatusTimeline(
                      status: booking.status,
                      started: state.startedAt != null,
                    ),
                  ],
                ),
              ),
              // While travelling / at the location (en-route + arrived, before work starts), fill
              // the empty space with an inline navigation map: the guard's own position + the
              // customer/destination + the straight route. Tap / expand opens the full-screen
              // navigation map. Only when the booking has site coordinates to plot.
              if ((stageOf(state) == JobStage.enRoute ||
                      stageOf(state) == JobStage.arrived ||
                      stageOf(state) == JobStage.start) &&
                  booking.lat != null &&
                  booking.lng != null) ...[
                const SizedBox(height: PgTokens.space4),
                _InlineNavMap(bookingId: bookingId, booking: booking),
              ],
              if (stageOf(state) == JobStage.working) ...[
                const SizedBox(height: PgTokens.space4),
                _WorkingPanel(bookingId: bookingId, state: state),
              ],
              if (state.error != null) ...[
                const SizedBox(height: PgTokens.space3),
                Text(state.error!,
                    style: const TextStyle(color: PgTokens.colorDanger)),
              ],
            ],
          ),
        ),
        _TransitionBar(bookingId: bookingId, state: state),
      ],
    );
  }
}

/// Locale-resolving wrapper around the shared [BookingStatusTimeline] for the guard active-job
/// screen (#123). `_Body` is a plain StatelessWidget, so this small Consumer reads the locale and
/// forwards the booking status + the client work-start flag to the SAME timeline the customer sees.
class _GuardStatusTimeline extends ConsumerWidget {
  const _GuardStatusTimeline({required this.status, required this.started});

  final BookingStatus status;
  final bool started;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    return BookingStatusTimeline(
      status: status,
      isThai: isThai,
      started: started,
    );
  }
}

/// #126: the PROMINENT awaiting-confirmation status card shown at the top of the guard's active-job
/// screen while the booking is `pending_completion` (the guard has requested completion and is now
/// waiting on the CUSTOMER to confirm). An emphasised amber card — a status icon + a bold
/// "รอลูกค้ายืนยันการจบงาน / Waiting for the customer to confirm completion" headline + a short
/// reassurance line — so the guard obviously understands they are BLOCKED on the customer, not stuck
/// in a broken flow. Purely informational (the action to leave for other jobs lives in the bottom
/// bar's awaiting case); driven by status, no timer.
class _AwaitingCustomerCard extends ConsumerWidget {
  const _AwaitingCustomerCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(PgTokens.space4),
      decoration: BoxDecoration(
        color: PgTokens.colorAmber50,
        borderRadius: BorderRadius.circular(PgTokens.radius2xl),
        border: Border.all(color: PgTokens.colorAmber200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // An emphasised status badge: a filled amber disc with an hourglass so the "waiting on
          // the customer" meaning reads at a glance, not just from the text.
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: PgTokens.colorAmber500,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.hourglass_top,
                size: 21, color: PgTokens.colorOnAmber),
          ),
          const SizedBox(width: PgTokens.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The bold, unambiguous headline: the guard is waiting on the CUSTOMER to confirm.
                Text(
                  isThai
                      ? 'รอลูกค้ายืนยันการจบงาน'
                      : 'Waiting for the customer to confirm completion',
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    color: PgTokens.colorAmber700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isThai
                      ? 'คุณส่งคำขอจบงานแล้ว — งานนี้รอลูกค้าตรวจสอบและยืนยัน คุณรับงานอื่นต่อได้เลย'
                      : "You've requested completion. This job is now with the customer for review "
                          '— you can take other jobs in the meantime.',
                  style: const TextStyle(
                      fontSize: 12.5, color: PgTokens.colorTextMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The customer-location card at the top of the active-job screen. #122: the whole card is now
/// TAPPABLE and carries an obvious "ดูรายละเอียดงาน / Job details" affordance that opens the SAME
/// [showBookingDetailsSheet] the customer's live screen uses — so the guard sees the identical job
/// spec (address + place type / schedule / hours / guard count / payment / status / total), not just
/// the bare address + the check-in timeline. Folded into THIS card (rather than a standalone block)
/// so it adds no height above the working panel. Reuses the shared sheet + the shared
/// [Booking.displayTotalSatang], so the guard's and customer's figures never drift.
class _AddressCard extends ConsumerWidget {
  const _AddressCard({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    // The booking carries only a free-text address (no lat/lng in the v2 contract), so we show
    // the address over a stylised area band rather than a real customer pin.
    return Material(
      color: PgTokens.colorGreen50,
      borderRadius: BorderRadius.circular(PgTokens.radius2xl),
      child: InkWell(
        borderRadius: BorderRadius.circular(PgTokens.radius2xl),
        onTap: () => showBookingDetailsSheet(
          context,
          booking: booking,
          totalSatang: booking.displayTotalSatang,
          isThai: isThai,
          // #127: the guard sees the customer's REAL NAME row (IDOR-gated resolve).
          showCustomer: true,
        ),
        child: Container(
          padding: const EdgeInsets.all(PgTokens.space4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(PgTokens.radius2xl),
            border: Border.all(color: PgTokens.colorGreen100),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.place_outlined,
                      color: PgTokens.colorGreen800, size: 22),
                  const SizedBox(width: PgTokens.space3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(isThai ? 'สถานที่ลูกค้า' : 'Customer location',
                            style: const TextStyle(
                                fontSize: 11, color: PgTokens.colorTextMuted)),
                        Text(booking.address ?? '—',
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: PgTokens.space3),
              const _MiniMapBand(),
              const SizedBox(height: PgTokens.space2),
              // The obvious #122 entry: a "ดูรายละเอียดงาน / Job details" row with a chevron, so the
              // tappable card visibly advertises the full details sheet (not a hidden tap target).
              Row(
                children: [
                  const Icon(Icons.receipt_long_outlined,
                      size: 16, color: PgTokens.colorGreen800),
                  const SizedBox(width: PgTokens.space2),
                  Expanded(
                    child: Text(
                      isThai ? 'ดูรายละเอียดงาน' : 'Job details',
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: PgTokens.colorGreen800),
                    ),
                  ),
                  const Icon(Icons.chevron_right,
                      size: 18, color: PgTokens.colorGreen800),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Design `.sb-mini-map`: a decorative 50px map band with a teardrop location pin (no real map —
/// the v2 booking has no lat/lng, and no ETA badge for the same reason).
class _MiniMapBand extends StatelessWidget {
  const _MiniMapBand();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: PgTokens.colorSunken, // nearest token to design #E7ECE7
        borderRadius: BorderRadius.circular(PgTokens.radiusLg),
      ),
      child: Center(
        // Design `.gpin`: 18px teardrop — `border-radius: 50% 50% 50% 2px` rotated 45deg.
        child: Transform.rotate(
          angle: math.pi / 4,
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: PgTokens.colorPrimary, // status-working green
              border: Border.all(color: PgTokens.colorSurface, width: 2),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(9),
                topRight: Radius.circular(9),
                bottomRight: Radius.circular(9),
                bottomLeft: Radius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Inline navigation map embedded in the guard's active-job screen while travelling / at the
/// location: the guard's OWN live position + the customer/destination + the straight route between
/// them, in a ~220px [TravelMapPreview] card. Reuses the SAME data + markers the full-screen guard
/// navigation ([GuardNavigationScreen]) uses — destination from the booking's `lat`/`lng`, self
/// from [guardSelfLocationProvider] (a LIVE device-GPS stream — the same fixes the guard sends to
/// presence). Tap / fullscreen expands to `/guard/active/{id}/navigate`. No self fix yet degrades
/// to a calm placeholder.
class _InlineNavMap extends ConsumerWidget {
  const _InlineNavMap({required this.bookingId, required this.booking});

  final String bookingId;
  final Booking booking;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dest = (booking.lat != null && booking.lng != null)
        ? GeoPoint(booking.lat!, booking.lng!)
        : null;
    final self = ref.watch(guardSelfLocationProvider).valueOrNull;
    // Reuse the SAME cached road route the full-screen nav map fetches (keyed by the snapped
    // origin/dest) — the preview never triggers its own OSRM request, and it shows the real road
    // line when available (else TravelMapPreview falls back to the straight segment).
    final route = (self != null && dest != null)
        ? ref
            .watch(guardRouteProvider(
              start: snapOrigin(self),
              end: snapDest(dest),
            ))
            .valueOrNull
        : null;
    return TravelMapPreview(
      mover: self,
      target: dest,
      routePoints: route?.polyline,
      moverMarker: const GuardNavGuardMarker(),
      targetMarker: const GuardNavDestMarker(),
      onExpand: () => context.push('/guard/active/$bookingId/navigate'),
    );
  }
}

/// Working panel: a live display countdown + the hourly check-in status. Owns a 1s DISPLAY timer
/// (allowed — it is not status polling) that re-reads the pure [WorkClock]/[CheckInSchedule].
class _WorkingPanel extends ConsumerStatefulWidget {
  const _WorkingPanel({required this.bookingId, required this.state});

  final String bookingId;
  final ActiveJobState state;

  @override
  ConsumerState<_WorkingPanel> createState() => _WorkingPanelState();
}

class _WorkingPanelState extends ConsumerState<_WorkingPanel> {
  Timer? _ticker;

  /// Fired-once guard for the auto-complete: the 1s ticker re-evaluates "time up" every second,
  /// so without this it would re-PUT /complete repeatedly. Set the instant we kick off the auto
  /// completion (BEFORE the await) so a re-entrant tick can never double-fire it.
  bool _autoCompleted = false;

  @override
  void initState() {
    super.initState();
    // Display-only 1s tick to refresh the countdown + due state. NOT status polling.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
      _maybeAutoComplete();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// Auto-close the job once the booked duration has fully ELAPSED while the guard app sits on
  /// the active-job screen — so the guard no longer has to remember to tap "จบงาน" at the end.
  /// Fires the SAME completion path the manual button uses (PUT /complete → pending_completion),
  /// exactly ONCE, and only while the job is still genuinely working (arrived + started, NOT
  /// already pending_completion/completed). The customer then approves via the existing flow.
  ///
  /// NOTE: this only fires while the guard app is open on THIS screen. A server-side scheduled
  /// auto-complete (for when the app is backgrounded/closed) is a backend follow-up — not built here.
  Future<void> _maybeAutoComplete() async {
    if (_autoCompleted) return;

    // Read the LIVE controller state (not the captured widget.state) so the status/busy checks
    // reflect any transition that landed since this panel was built.
    final live = ref.read(activeJobControllerProvider(widget.bookingId)).valueOrNull;
    if (live == null || live.busy) return;

    // Only auto-fire while still working: arrived + started, with the countdown known. The instant
    // the status advances (pending_completion/completed) this is no longer JobStage.working and we
    // must not fire (the guard may have closed early, or the customer already approved).
    if (live.booking.status != BookingStatus.arrived) return;
    final clock = live.clock;
    if (clock == null) return;
    if (!clock.isTimeUp(DateTime.now().toUtc())) return;

    // Claim the single shot BEFORE awaiting the network so re-entrant ticks bail at the top.
    _autoCompleted = true;
    final isThai = ref.read(localeControllerProvider) == AppLocale.th;
    final ok = await ref
        .read(activeJobControllerProvider(widget.bookingId).notifier)
        .complete();
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isThai
              ? 'ครบเวลาทำงาน — ส่งจบงานให้ลูกค้าตรวจสอบ'
              : "Time's up — sent to the customer for review"),
        ),
      );
    } else {
      // The PUT failed (e.g. transient/409 because the status already advanced). Release the flag
      // so a later tick can retry; the controller already surfaced the error in state.error.
      _autoCompleted = false;
    }
  }

  /// The scheduled clock time of check-in slot [i] (startedAt + i hours), local "HH:MM".
  static String _slotTime(DateTime startedAt, int i) {
    final l = startedAt.add(Duration(hours: i)).toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(l.hour)}:${two(l.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    final state = widget.state;
    final clock = state.clock;
    final schedule = state.schedule;
    if (clock == null || schedule == null) {
      return const SizedBox.shrink();
    }
    final now = DateTime.now().toUtc();
    final dueIndex = schedule.dueIndex(now);
    final startedAt = clock.startedAt; // clock != null ⟹ startedAt was set

    // The guard's own submitted reports (participants-only `GET …/progress-reports`, the same
    // source the customer live screen reads), keyed by the server's 1-based hour_number, so a
    // "Reported" row opens its photo + GPS + note. Slot i ↔ hour i+1. A failed/empty read just
    // leaves the rows non-tappable (no regression). Watched: re-pulls when status changes.
    final reportsByHour = <int, ProgressReport>{
      for (final r in ref
              .watch(progressReportsControllerProvider(widget.bookingId))
              .valueOrNull
              ?.reports ??
          const <ProgressReport>[])
        r.hourNumber: r,
    };

    return Container(
      padding: const EdgeInsets.all(PgTokens.space4),
      decoration: BoxDecoration(
        color: PgTokens.colorSurface,
        borderRadius: BorderRadius.circular(PgTokens.radius2xl),
        border: Border.all(color: PgTokens.colorBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Design G4: the 74px ring countdown (shared widget) — shift window + elapsed + bar.
          WorkCountdownRing(clock: clock, isThai: isThai),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: PgTokens.space3),
            child: Divider(height: 1, color: PgTokens.colorBorder),
          ),
          // Design `.timeline` header: "ความคืบหน้า · 2 จาก 5 จุด".
          Text(
            isThai
                ? 'ความคืบหน้า · ${state.completedCheckIns.length} จาก ${schedule.totalSlots} จุด'
                : 'Progress · ${state.completedCheckIns.length} of ${schedule.totalSlots}',
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: PgTokens.colorText),
          ),
          const SizedBox(height: PgTokens.space3),
          // Per-hour vertical timeline (shared widget). Slot i ↔ server hour i+1; the timestamp
          // is the scheduled due time (startedAt + i h) — per-report notes/photos are a follow-up.
          for (var i = 0; i < schedule.totalSlots; i++)
            CheckInTimelineRow(
              index: i + 1,
              title: i == 0
                  ? (isThai ? 'เริ่มงาน · เช็คอินจุดนัด' : 'Start · check in')
                  : (isThai ? 'ตรวจรอบที่ $i' : 'Round $i check-in'),
              done: state.completedCheckIns.contains(i),
              isCurrent: i == dueIndex && !state.completedCheckIns.contains(i),
              isLast: i == schedule.totalSlots - 1,
              time: _slotTime(startedAt, i),
              statusLabel: state.completedCheckIns.contains(i)
                  ? (isThai ? 'รายงานแล้ว' : 'Reported')
                  : i == dueIndex
                      ? (isThai ? 'ถึงกำหนด' : 'Due now')
                      : i < dueIndex
                          ? (isThai ? 'พลาด' : 'Missed')
                          : (isThai ? 'รอเช็คอิน' : 'Pending'),
              // Slot i is server hour i+1; a submitted report opens its photo+GPS+note.
              onTap: reportsByHour[i + 1] == null
                  ? null
                  : () => showProgressReportViewer(
                        context,
                        report: reportsByHour[i + 1]!,
                        isThai: isThai,
                      ),
            ),
          // #98: the PRIMARY job action (check-in / end) lives in ONE place — the bottom
          // [_WorkingActionBar], not here. The panel is now purely the read-only progress
          // (countdown + timeline); the guard no longer hunts between an in-panel check-in
          // button and a separate bottom "End" button.
        ],
      ),
    );
  }
}

class _TransitionBar extends ConsumerWidget {
  const _TransitionBar({required this.bookingId, required this.state});

  final String bookingId;
  final ActiveJobState state;

  Future<bool?> _confirm(
      BuildContext context, bool isThai, String title, String body) {
    return showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(isThai ? 'ยกเลิก' : 'Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(isThai ? 'ยืนยัน' : 'Confirm')),
        ],
      ),
    );
  }

  /// Return the guard to their "งานของฉัน / My Jobs" list after a job leaves their hands
  /// (awaiting the customer, or completed). Two problems this fixes (#121):
  ///
  ///   1. STALE LIST — the jobs list ([guardJobsControllerProvider]) is a cached fetch that is NOT
  ///      refetched on completion, so the just-completed job lingers in "กำลังทำ / Active" instead
  ///      of moving to "เสร็จ / Done". Invalidate it FIRST so the list this navigation lands on is
  ///      rebuilt from a fresh `GET /bookings` (the completed job now partitions into the Done tab).
  ///
  ///   2. FROZEN BACK — a bare `context.go('/guard/jobs')` REPLACES the whole navigation stack with
  ///      a single page rooted at the jobs list (My Jobs is normally a PUSHED child of the guard
  ///      home, not a root). Its header back button then has nothing to pop → the screen looks
  ///      frozen and the guard force-closes the app. Rebuild a real, poppable stack instead
  ///      (home → jobs) so back returns to the dashboard normally, no restart needed.
  ///
  /// Single-tap / idempotent: `context.go` is a stack reset, so a double-tap just re-lands on the
  /// same two-page stack — it can never deepen it or strand the guard.
  void _backToJobs(BuildContext context, WidgetRef ref) {
    ref.invalidate(guardJobsControllerProvider);
    context.go('/home/guard');
    context.push('/guard/jobs');
  }

  Future<void> _complete(
      BuildContext context, WidgetRef ref, bool isThai) async {
    // Capture the notifier + messenger BEFORE the dialog await so we never touch `ref`/`context`
    // post-await (the bar may rebuild as the status advances).
    final notifier = ref.read(activeJobControllerProvider(bookingId).notifier);
    final messenger = ScaffoldMessenger.of(context);
    final yes = await _confirm(
      context,
      isThai,
      isThai ? 'จบงาน?' : 'Complete job?',
      isThai
          ? 'ส่งคำขอจบงานให้ลูกค้าตรวจสอบ — ย้อนกลับไม่ได้'
          : 'This requests completion and cannot be undone.',
    );
    if (yes != true) return;
    // #99b: SINGLE-TAP with clear feedback. `complete()` is busy-gated (a re-tap is ignored while
    // in-flight) and idempotent on the controller side. Confirm success with a snackbar so the
    // guard isn't left wondering whether it registered (the panel silently swapping to "awaiting"
    // is what drove the reported re-tapping). A failure (e.g. 409 because the status already
    // advanced) leaves the controller's state.error on screen.
    final ok = await notifier.complete();
    if (ok) {
      messenger.showSnackBar(SnackBar(
        content: Text(isThai
            ? 'ส่งจบงานให้ลูกค้าตรวจสอบแล้ว'
            : 'Sent to the customer for review'),
      ));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    final ctrl = ref.read(activeJobControllerProvider(bookingId).notifier);
    final stage = stageOf(state);
    final busy = state.busy;

    Widget bar(Widget child) => Container(
          padding: const EdgeInsets.all(PgTokens.space4),
          decoration: const BoxDecoration(
            color: PgTokens.colorSurface,
            border: Border(top: BorderSide(color: PgTokens.colorBorder)),
          ),
          child: SafeArea(top: false, child: child),
        );

    switch (stage) {
      case JobStage.enRoute:
        // PRE-PAY gate: `en_route` requires the customer to have PAID (booking.paid_at set, via
        // the payment.completed event). Until then the backend 409s the transition, so the CTA is
        // disabled and we show "รอลูกค้าชำระเงิน". paid_at arrives on the GET snapshot (the WS
        // frame carries only the status), so the screen re-pulls / re-enters reflect it.
        final paid = state.booking.isPaid;
        return bar(Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!paid) ...[
              _AwaitingPaymentNotice(isThai: isThai),
              const SizedBox(height: PgTokens.space2),
            ],
            PgPrimaryButton(
              label: isThai ? 'เริ่มเดินทาง' : 'Go en route',
              busy: busy,
              onPressed: (busy || !paid) ? null : () => ctrl.enRoute(),
            ),
            const SizedBox(height: PgTokens.space1),
            // Opens the full withdraw flow (warning banner + reason + admin notes) —
            // replaces the old bare AlertDialog confirm.
            PgGhostButton(
              label: isThai ? 'ปฏิเสธงาน' : 'Withdraw',
              onPressed: busy
                  ? null
                  : () => context.push('/guard/active/$bookingId/withdraw'),
            ),
          ],
        ));
      case JobStage.arrived:
        // When the booking has site coordinates, route the guard through the full-screen
        // navigation map (which confirms arrival + starts work in one CTA). Older bookings
        // without coords keep the plain "Arrived" action.
        return bar(
          (state.booking.lat != null && state.booking.lng != null)
              ? PgPrimaryButton(
                  label: isThai ? 'นำทาง' : 'Navigate',
                  busy: busy,
                  onPressed: busy
                      ? null
                      : () => context.push('/guard/active/$bookingId/navigate'),
                )
              : PgPrimaryButton(
                  label: isThai ? 'ถึงแล้ว' : 'Arrived',
                  busy: busy,
                  onPressed: busy ? null : () => ctrl.arrived(),
                ),
        );
      case JobStage.start:
        // Design G3: the start CTA pulses (`.sb-btn.amber.pulse`).
        return bar(_PulsingGlow(
          child: PgPrimaryButton(
            label: isThai ? 'เริ่มงาน' : 'Start job',
            color: PgTokens.colorAccent,
            foreground: PgTokens.colorOnAmber,
            busy: busy,
            onPressed: busy ? null : () => ctrl.start(),
          ),
        ));
      case JobStage.working:
        // #98: the ONE primary working action lives here (not in the panel). It reflects the
        // current sub-stage: a due check-in (เช็คอินเริ่มงาน → … → hourly) takes the primary slot,
        // with "จบงาน/End" as the secondary; when no check-in is due, "จบงาน/End" is primary.
        return bar(_WorkingActionBar(
          bookingId: bookingId,
          state: state,
          onComplete: () => _complete(context, ref, isThai),
        ));
      case JobStage.awaiting:
        return bar(Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
                isThai ? 'รอลูกค้าตรวจสอบการจบงาน' : 'Awaiting customer review',
                textAlign: TextAlign.center,
                style: const TextStyle(color: PgTokens.colorTextMuted)),
            const SizedBox(height: PgTokens.space3),
            // #99a: the guard is NOT stuck here — a clear primary returns them to their jobs list
            // so they can pick up the next job while this one awaits the customer's approval.
            PgPrimaryButton(
              label: isThai ? 'กลับไปหน้างานของฉัน' : 'Back to my jobs',
              onPressed: () => _backToJobs(context, ref),
            ),
            const SizedBox(height: PgTokens.space1),
            // Design G5: chatting the customer + viewing live status are the secondary actions.
            _ChatCustomerButton(booking: state.booking),
            PgGhostButton(
              label: isThai ? 'ดูสถานะสด' : 'View live status',
              onPressed: () => context.push('/booking/$bookingId/live'),
            ),
          ],
        ));
      case JobStage.done:
        // A NEGATIVE terminal (the customer CANCELLED, or the job was declined) is NOT a completion
        // — render a distinct cancelled banner + a prominent "back to jobs" primary so the guard is
        // never trapped on a dead job with only chat/call/details. The success "Job completed" view
        // below is reserved for an actual `completed`.
        if (BookingLifecycle.isNegativeTerminal(state.booking.status)) {
          return bar(_CancelledBar(bookingId: bookingId, state: state));
        }
        // #99a + #99c: the completed view is NOT a dead-end and is NOT a rating CTA (rating is
        // customer-only, #97). The guard gets a neutral completion state + the receipt + a clear
        // path back to take new jobs.
        return bar(Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(PgTokens.space3),
              decoration: BoxDecoration(
                color: PgTokens.colorSuccessBg,
                borderRadius: BorderRadius.circular(PgTokens.radiusLg),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle,
                      size: 18, color: PgTokens.colorSuccess),
                  const SizedBox(width: PgTokens.space2),
                  Expanded(
                    child: Text(
                      isThai ? 'งานเสร็จสมบูรณ์' : 'Job completed',
                      style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: PgTokens.colorSuccess),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: PgTokens.space3),
            PgPrimaryButton(
              label: isThai ? 'กลับไปรับงานใหม่' : 'Take new jobs',
              onPressed: () => _backToJobs(context, ref),
            ),
            const SizedBox(height: PgTokens.space1),
            // The receipt the guard can see (booking-derived — a guard cannot read the customer's
            // payment; the settled bill needs a participants-scoped endpoint, flagged as a backend
            // follow-up in job_receipt_sheet.dart).
            PgGhostButton(
              label: isThai ? 'ดูใบสรุปค่าบริการ' : 'View receipt',
              onPressed: () => showJobReceiptSheet(
                context,
                booking: state.booking,
                payment: null,
                isThai: isThai,
              ),
            ),
            PgGhostButton(
              label: isThai ? 'ดูสถานะสด' : 'View live status',
              onPressed: () => context.push('/booking/$bookingId/live'),
            ),
          ],
        ));
    }
  }
}

/// FIX #2 — the terminal bottom bar shown when the job is CANCELLED (or declined) out from under the
/// guard, chiefly by the CUSTOMER cancelling mid-job. A clear cancelled banner + a PROMINENT primary
/// "กลับไปรับงานใหม่ / Back to jobs" that returns the guard to the job pool so they are never trapped
/// on a dead job. Navigates to the guard home AND invalidates [guardJobsControllerProvider] so the
/// pool re-fetches (the just-cancelled job drops out of the active list — see
/// [GuardJobsController.active]). Chat/details stay available as secondary actions for any follow-up.
class _CancelledBar extends ConsumerWidget {
  const _CancelledBar({required this.bookingId, required this.state});

  final String bookingId;
  final ActiveJobState state;

  /// Return the guard to the job pool. Invalidate the jobs list FIRST so the screen we land on
  /// rebuilds from a fresh `GET /bookings` (the cancelled job is no longer in [active]).
  void _backToJobs(BuildContext context, WidgetRef ref) {
    ref.invalidate(guardJobsControllerProvider);
    context.go('/home/guard');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // The unambiguous cancelled banner — danger-toned so it can't be mistaken for completion.
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(PgTokens.space3),
          decoration: BoxDecoration(
            color: PgTokens.colorDangerBg,
            borderRadius: BorderRadius.circular(PgTokens.radiusLg),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.cancel_outlined,
                  size: 18, color: PgTokens.colorDanger),
              const SizedBox(width: PgTokens.space2),
              Expanded(
                child: Text(
                  isThai ? 'งานนี้ถูกยกเลิกแล้ว' : 'This job was cancelled',
                  style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: PgTokens.colorDanger),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: PgTokens.space3),
        // The PROMINENT primary: get the guard back to the job pool.
        PgPrimaryButton(
          label: isThai ? 'กลับไปรับงานใหม่' : 'Back to jobs',
          onPressed: () => _backToJobs(context, ref),
        ),
        const SizedBox(height: PgTokens.space1),
        // Chat + details stay available as SECONDARY actions for any follow-up the guard needs.
        _ChatCustomerButton(booking: state.booking),
        PgGhostButton(
          label: isThai ? 'ดูรายละเอียดงาน' : 'Job details',
          onPressed: () => showBookingDetailsSheet(
            context,
            booking: state.booking,
            totalSatang: state.booking.displayTotalSatang,
            isThai: isThai,
            showCustomer: true,
          ),
        ),
      ],
    );
  }
}

/// #98 — the SINGLE primary working action, in the bottom bar (consolidated from the old split
/// between an in-panel "เช็คอินเริ่มงาน" button and a separate bottom "จบงาน" button). It reflects
/// the current sub-stage of the working window:
///   • a check-in is DUE → the check-in CTA is primary (เช็คอินเริ่มงาน at slot 0, then hourly),
///     with "จบงาน/End" as a secondary so the guard can still end early;
///   • nothing due → "จบงาน/End" is the primary.
///
/// Owns a 1s DISPLAY ticker (NOT status polling — like [_WorkingPanel]) so the due-state refreshes
/// as the shift's hour boundaries pass, keeping the bottom action correct without a manual refresh.
/// Both actions are busy-gated off the controller state so a re-tap mid-flight is a no-op (#99b).
class _WorkingActionBar extends ConsumerStatefulWidget {
  const _WorkingActionBar({
    required this.bookingId,
    required this.state,
    required this.onComplete,
  });

  final String bookingId;
  final ActiveJobState state;
  final VoidCallback onComplete;

  @override
  ConsumerState<_WorkingActionBar> createState() => _WorkingActionBarState();
}

class _WorkingActionBarState extends ConsumerState<_WorkingActionBar> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Display-only 1s tick so the due-state (and thus which action is primary) stays current as
    // hour boundaries pass. NOT status polling — it only re-reads the pure [CheckInSchedule].
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _checkIn(int slot) async {
    final isThai = ref.read(localeControllerProvider) == AppLocale.th;
    final store = ref.read(workSessionStoreProvider);
    // Mark the check-in in flight for the WHOLE sheet lifecycle — the photo capture opens the
    // system camera and backgrounds the app, so the screen's `resumed` handler must NOT re-fetch
    // (and wipe the working session) until the sheet closes. Always cleared in `finally` so a
    // cancel / error can never leave resync permanently suppressed.
    store.beginCheckIn(widget.bookingId);
    final bool? ok;
    try {
      ok = await showCheckInSheet(
        context: context,
        ref: ref,
        bookingId: widget.bookingId,
        hourNumber: slot,
      );
    } finally {
      store.endCheckIn(widget.bookingId);
    }
    if (ok == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isThai ? 'ส่งรายงานเช็คอินแล้ว' : 'Check-in sent'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    final state = widget.state;
    final busy = state.busy;
    final schedule = state.schedule;

    final endButton = PgPrimaryButton(
      label: isThai ? 'จบงาน' : 'End',
      busy: busy,
      onPressed: busy ? null : widget.onComplete,
    );

    // Without a schedule yet (clock not started) just show End — the start stage is handled by a
    // different case, so reaching here means working with the schedule available in practice.
    if (schedule == null) return endButton;

    final now = DateTime.now().toUtc();
    final dueIndex = schedule.dueIndex(now);
    final dueNow = schedule.isDueNow(now, state.completedCheckIns);

    if (!dueNow) return endButton;

    // A check-in is due → make it the PRIMARY action; keep End as the secondary so the guard can
    // still finish early. Slot 0 is the start check-in ("เช็คอินเริ่มงาน").
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        PgPrimaryButton(
          label: dueIndex == 0
              ? (isThai ? 'เช็คอินเริ่มงาน' : 'Start check-in')
              : (isThai
                  ? 'เช็คอินชั่วโมงที่ $dueIndex'
                  : 'Hour $dueIndex check-in'),
          color: PgTokens.colorAccent,
          foreground: PgTokens.colorOnAmber,
          busy: busy,
          onPressed: busy ? null : () => _checkIn(dueIndex),
        ),
        const SizedBox(height: PgTokens.space1),
        PgGhostButton(
          label: isThai ? 'จบงาน' : 'End',
          onPressed: busy ? null : widget.onComplete,
        ),
      ],
    );
  }
}

/// The guard-side PRE-PAY gate notice shown above the disabled "Go en route" CTA while the
/// customer has not paid yet ("รอลูกค้าชำระเงิน" / "Awaiting customer payment").
class _AwaitingPaymentNotice extends StatelessWidget {
  const _AwaitingPaymentNotice({required this.isThai});

  final bool isThai;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(PgTokens.space3),
      decoration: BoxDecoration(
        color: PgTokens.colorWarningBg,
        borderRadius: BorderRadius.circular(PgTokens.radiusLg),
      ),
      child: Row(
        children: [
          const Icon(Icons.hourglass_empty,
              size: 16, color: PgTokens.colorWarning),
          const SizedBox(width: PgTokens.space2),
          Expanded(
            child: Text(
              isThai ? 'รอลูกค้าชำระเงิน' : 'Awaiting customer payment',
              style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: PgTokens.colorWarning),
            ),
          ),
        ],
      ),
    );
  }
}

/// Design `@keyframes btnpulse`: a 1.8s repeating glow — a [PgTokens.colorAccent] shadow that
/// spreads 0→8px while fading 0.4→0 opacity. Display-only animation around the start CTA.
class _PulsingGlow extends StatefulWidget {
  const _PulsingGlow({required this.child});

  final Widget child;

  @override
  State<_PulsingGlow> createState() => _PulsingGlowState();
}

class _PulsingGlowState extends State<_PulsingGlow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_controller.value);
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(PgTokens.radiusXl),
            boxShadow: [
              BoxShadow(
                color: PgTokens.colorAccent.withValues(alpha: 0.4 * (1 - t)),
                spreadRadius: 8 * t,
              ),
            ],
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// Design G5's single CTA: chat the customer. Same find-or-create conversation flow as
/// [ChatEntryButton] (guarded by a busy flag — `POST /conversations` is not idempotent).
class _ChatCustomerButton extends ConsumerStatefulWidget {
  const _ChatCustomerButton({required this.booking});

  final Booking booking;

  @override
  ConsumerState<_ChatCustomerButton> createState() =>
      _ChatCustomerButtonState();
}

class _ChatCustomerButtonState extends ConsumerState<_ChatCustomerButton> {
  bool _busy = false;

  Future<void> _open() async {
    final isThai = ref.read(localeControllerProvider) == AppLocale.th;
    final booking = widget.booking;
    final myUserId = ref.read(sessionProvider).user?.userId;
    if (myUserId == null || _busy) return;

    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final launcher = ref.read(chatLauncherProvider);

    setState(() => _busy = true);
    try {
      final conversationId = await launcher.resolveConversationId(
        requestId: booking.id,
        acting: ChatRole.guard,
        requestStatus: booking.status.wire,
        participants: [
          ParticipantInput(userId: myUserId, role: ChatRole.guard),
          ParticipantInput(userId: booking.customerId, role: ChatRole.customer),
        ],
      );
      if (!mounted) return;
      await router.push(ChatRoutes.conversation(
        conversationId,
        acting: ChatRole.guard,
        readOnly: ChatReadOnly.fromStatus(booking.status.wire),
      ));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(SnackBar(
          content: Text(isThai ? 'เปิดแชทไม่สำเร็จ' : 'Could not open chat')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    return PgGhostButton(
      label: isThai ? 'แชตหาลูกค้า' : 'Chat customer',
      onPressed: _busy ? null : _open,
    );
  }
}
