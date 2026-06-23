import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../core/controllers/booking_flow_controller.dart';
import '../../core/controllers/locale_controller.dart';
import '../../widgets/pg_error_state.dart';
import '../../widgets/pguard_header.dart';
import '../../widgets/primary_button.dart';
import 'widgets/guard_card.dart';
import 'widgets/guard_reviews_sheet.dart';

/// Step 3 — guard discovery. Loads `GET /v1/available-guards` ONCE (no polling) and shows the
/// approved guards with their rating summary. v2 is first-come-accept: choosing a guard here is
/// a preview preference, not an assignment (no `/assign` endpoint exists); a nearby guard
/// accepts the request later, surfaced on the live-status screen. UI per
/// `Mobile - Customer App.html` (nearby guards).
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

  /// "ยืนยันการจอง" / Confirm — this is where the booking is CREATED (fixes #79: guards only see
  /// the open job AFTER the customer confirms, not at the form step). The radio-selected guard is a
  /// non-binding PREVIEW; v2 stays first-come, so we send no `guard_id`. On success, route to live
  /// status; `createBooking` records its own error into the flow state for [PgErrorState] / inline.
  Future<void> _confirm() async {
    final ok = await ref.read(bookingFlowControllerProvider.notifier).createBooking();
    if (!ok || !mounted) return;
    final id = ref.read(bookingFlowControllerProvider).booking?.id;
    if (id != null) context.go('/booking/$id/live');
  }

  @override
  Widget build(BuildContext context) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    final state = ref.watch(bookingFlowControllerProvider);
    final ctrl = ref.read(bookingFlowControllerProvider.notifier);

    return Scaffold(
      backgroundColor: PgTokens.colorBg,
      appBar: PGuardHeader(light: true,
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
              // Enabled once guards are loaded and we are not mid-request. Confirm CREATES the
              // booking; no pre-existing booking is required (it doesn't exist yet by design).
              enabled: !state.busy && state.guards.isNotEmpty,
              busy: state.busy,
              // Post-pay: confirm creates the booking then goes straight to live status (no up-front
              // payment). A guard accepts first-come; billing is on completion.
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
        // First-come note demoted to a plain caption (the design's guard list has no banner
        // between the header and the cards).
        Text(
          isThai
              ? 'เจ้าหน้าที่ที่ว่างจะตอบรับงานของคุณ (first-come) — เลือกคนที่สนใจไว้เพื่อดูเรตติ้งได้'
              : 'An available guard will accept your job (first-come) — pick one '
                  'you like to see their rating',
          style: const TextStyle(fontSize: 12, color: PgTokens.colorTextMuted),
        ),
        const SizedBox(height: PgTokens.space3),
        for (final guard in state.guards) ...[
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
  });

  final bool enabled;
  final bool busy;
  final VoidCallback onContinue;
  final bool isThai;

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
        child: PgPrimaryButton(
          // Confirm CREATES the booking (fixes #79) — show the spinner while the POST is in flight.
          label: isThai ? 'ยืนยันการจอง' : 'Confirm booking',
          busy: busy,
          onPressed: enabled ? onContinue : null,
        ),
      ),
    );
  }
}
