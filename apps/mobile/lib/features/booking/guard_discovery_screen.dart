import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../core/controllers/booking_flow_controller.dart';
import '../../core/controllers/locale_controller.dart';
import '../../core/models/geo.dart';
import '../../widgets/pg_error_state.dart';
import '../../widgets/pguard_header.dart';
import '../../widgets/primary_button.dart';
import 'widgets/guard_card.dart';
import 'widgets/guard_reviews_sheet.dart';

/// Step 3 — guard discovery. Loads `GET /v1/available-guards` ONCE (no polling) and shows the
/// approved guards with their rating summary. DIRECTED OFFER (C3): the guard the customer picks
/// here IS the offer target — on confirm the booking is created with `target_guard_id`, so the
/// job is offered to ONLY that guard (no other guard sees or can accept it, server-enforced). No
/// auto-fallback to the open pool: if the chosen guard never takes it, the customer re-books to
/// pick someone else. Surfaced on the live-status screen. UI per `Mobile - Customer App.html`.
class GuardDiscoveryScreen extends ConsumerStatefulWidget {
  const GuardDiscoveryScreen({super.key});

  @override
  ConsumerState<GuardDiscoveryScreen> createState() =>
      _GuardDiscoveryScreenState();
}

class _GuardDiscoveryScreenState extends ConsumerState<GuardDiscoveryScreen> {
  @override
  void initState() {
    super.initState();
    // Single fetch on entry — NOT polling. Skip if we already have results (avoids a redundant
    // call on back-then-forward navigation); an empty/errored list still retries.
    if (ref.read(bookingFlowControllerProvider).guards.isEmpty) {
      Future.microtask(
          () => ref.read(bookingFlowControllerProvider.notifier).loadGuards());
    }
  }

  /// "ยืนยันการจอง" / Confirm — this is where the booking is CREATED (fixes #79: the guard only sees
  /// the job AFTER the customer confirms, not at the form step). DIRECTED OFFER (C3): the
  /// radio-selected guard is sent as `target_guard_id`, so the job is offered to ONLY them. On
  /// success, route to live status; `createBooking` records its own error into the flow state for
  /// [PgErrorState] / inline.
  Future<void> _confirm() async {
    final ok =
        await ref.read(bookingFlowControllerProvider.notifier).createBooking();
    if (!ok || !mounted) return;
    final id = ref.read(bookingFlowControllerProvider).booking?.id;
    // Build a POPPABLE stack (home → live) rather than a bare `context.go` that replaces the whole
    // booking-flow chain with just the live screen: a lone-root live screen leaves back (both the
    // header chevron and Android system back) with nothing to pop, which stranded the customer on a
    // guard-cancelled job. Rooting on home means back lands on the dashboard, not a dead end.
    if (id != null) {
      context.go('/home/customer');
      context.push('/booking/$id/live');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    final state = ref.watch(bookingFlowControllerProvider);
    final ctrl = ref.read(bookingFlowControllerProvider.notifier);

    return Scaffold(
      backgroundColor: PgTokens.colorBg,
      appBar: PGuardHeader(
        light: true,
        title: isThai ? 'เลือกเจ้าหน้าที่' : 'Choose a guard',
        subtitle: state.guards.isNotEmpty
            ? (isThai
                ? '${state.guards.length} คนพร้อมรับงาน'
                : '${state.guards.length} guards available')
            : 'Nearby guards',
        showBack: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: _body(state, ctrl, isThai)),
            // A create error from confirm (state.error with guards already loaded) shows inline
            // above the bar — the list/empty/error _body handles only the load phase.
            if (state.error != null && state.guards.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    PgTokens.space4, 0, PgTokens.space4, PgTokens.space2),
                child: Text(
                  state.error!,
                  style: const TextStyle(color: PgTokens.colorDanger),
                ),
              ),
            _ContinueBar(
              // Require a guard SELECTION before confirm works: enabled only once guards are
              // loaded, one is radio-selected (the DIRECTED offer target), and we are not
              // mid-request. Confirm CREATES the booking; no pre-existing booking is required
              // (it doesn't exist yet by design).
              enabled: !state.busy &&
                  state.guards.isNotEmpty &&
                  state.selectedGuardId != null,
              busy: state.busy,
              // A nudge shown under the disabled button when nothing is picked yet, so the gate is
              // explained rather than just inert. Cleared once a guard is selected.
              hint: state.guards.isNotEmpty && state.selectedGuardId == null
                  ? (isThai
                      ? 'เลือกเจ้าหน้าที่ที่ต้องการก่อน'
                      : 'Select a guard to continue')
                  : null,
              // Post-pay: confirm creates the booking (offered to the chosen guard) then goes
              // straight to live status (no up-front payment). Billing is on completion.
              onContinue: _confirm,
              isThai: isThai,
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(
      BookingFlowState state, BookingFlowController ctrl, bool isThai) {
    if (state.busy && state.guards.isEmpty) {
      return _SearchingState(isThai: isThai);
    }
    if (state.error != null && state.guards.isEmpty) {
      return PgErrorState(
        title: isThai ? 'หาเจ้าหน้าที่ไม่สำเร็จ' : 'Could not load guards',
        message: state.error,
        onRetry: ctrl.loadGuards,
      );
    }
    if (state.guards.isEmpty) {
      // Cross-state hero pattern: icon + 15px w600 title + 13px muted subtitle.
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(PgTokens.space6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.search_off_outlined,
                  size: 48, color: PgTokens.colorTextFaint),
              const SizedBox(height: PgTokens.space3),
              Text(
                isThai
                    ? 'ยังไม่มีเจ้าหน้าที่ว่างในขณะนี้'
                    : 'No guards available right now',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: PgTokens.colorText),
              ),
            ],
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(PgTokens.space4),
      children: [
        // Directed-offer note demoted to a plain caption (the design's guard list has no banner
        // between the header and the cards): the customer picks ONE guard and the job is offered
        // to only them.
        Text(
          isThai
              ? 'เลือกเจ้าหน้าที่ 1 คน — งานจะถูกส่งให้เฉพาะคนที่คุณเลือกเท่านั้น'
              : 'Pick one guard — the job is offered to only the guard you choose',
          style: const TextStyle(fontSize: 12, color: PgTokens.colorTextMuted),
        ),
        const SizedBox(height: PgTokens.space3),
        for (final guard in state.guards) ...[
          // C2: the list arrives already sorted NEAREST-first. When the server measured a
          // distance (a meetup point was sent + the guard's live position was known), show a small
          // "~1.2 กม." caption above the card. Straight-line → the `~` marks it approximate.
          if (guard.distanceMeters != null)
            Padding(
              padding: const EdgeInsets.only(
                  left: PgTokens.space1, bottom: PgTokens.space1),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.near_me_outlined,
                      size: 13, color: PgTokens.colorTextMuted),
                  const SizedBox(width: 4),
                  Text(
                    isThai
                        ? 'ห่าง ~${formatDistance(guard.distanceMeters!, thai: true)}'
                        : '~${formatDistance(guard.distanceMeters!, thai: false)} away',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: PgTokens.colorTextMuted),
                  ),
                ],
              ),
            ),
          GuardCard(
            guard: guard,
            selected: guard.guardId == state.selectedGuardId,
            onTap: () => ctrl.selectGuard(guard.guardId),
            // Distinct affordance: opens the read-only reviews sheet without selecting the guard.
            onViewReviews: () => showGuardReviewsSheet(
              context: context,
              guardId: guard.guardId,
            ),
          ),
          const SizedBox(height: PgTokens.space3),
        ],
      ],
    );
  }
}

/// The design's "searching" state: centered title + three staggered pulsing dots
/// (10px, brand interactive, 8px gap). One repeating display animation — no polling.
class _SearchingState extends StatefulWidget {
  const _SearchingState({required this.isThai});

  final bool isThai;

  @override
  State<_SearchingState> createState() => _SearchingStateState();
}

class _SearchingStateState extends State<_SearchingState>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// One 10px dot whose pulse starts [delay] (fraction of the cycle ≈ .2s steps) late.
  Widget _dot(double delay) {
    final opacity = _controller.drive(
      Tween<double>(begin: 0.25, end: 1).chain(
        CurveTween(
          curve: Interval(delay, (delay + 0.6).clamp(0.0, 1.0),
              curve: Curves.easeInOut),
        ),
      ),
    );
    return FadeTransition(
      opacity: opacity,
      child: Container(
        width: 10,
        height: 10,
        decoration: const BoxDecoration(
          color: PgTokens.colorPrimary,
          shape: BoxShape.circle,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(PgTokens.space6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.isThai
                  ? 'กำลังค้นหาเจ้าหน้าที่ใกล้คุณ'
                  : 'Finding nearby guards',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: PgTokens.space6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _dot(0),
                const SizedBox(width: PgTokens.space2),
                _dot(0.2),
                const SizedBox(width: PgTokens.space2),
                _dot(0.4),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ContinueBar extends StatelessWidget {
  const _ContinueBar({
    required this.enabled,
    required this.busy,
    required this.onContinue,
    required this.isThai,
    this.hint,
  });

  final bool enabled;
  final bool busy;
  final VoidCallback onContinue;
  final bool isThai;

  /// Optional caption shown above a DISABLED button to explain the gate ("select a guard first").
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(PgTokens.space4),
      decoration: const BoxDecoration(
        color: PgTokens.colorSurface,
        border: Border(top: BorderSide(color: PgTokens.colorBorder)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hint != null) ...[
              Text(
                hint!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 12.5, color: PgTokens.colorTextMuted),
              ),
              const SizedBox(height: PgTokens.space2),
            ],
            PgPrimaryButton(
              // Confirm CREATES the booking (fixes #79) — show the spinner while the POST is in
              // flight. Gated on a guard selection (the customer's first-come preference).
              label: isThai ? 'ยืนยันการจอง' : 'Confirm booking',
              busy: busy,
              onPressed: enabled ? onContinue : null,
            ),
          ],
        ),
      ),
    );
  }
}
