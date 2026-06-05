import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../core/controllers/booking_flow_controller.dart';
import '../../widgets/pguard_header.dart';
import '../../widgets/primary_button.dart';
import 'widgets/guard_card.dart';

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

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(bookingFlowControllerProvider);
    final ctrl = ref.read(bookingFlowControllerProvider.notifier);

    return Scaffold(
      backgroundColor: PgTokens.colorBg,
      appBar: PGuardHeader(
        title: 'เลือกเจ้าหน้าที่',
        subtitle: state.guards.isNotEmpty
            ? '${state.guards.length} คนพร้อมรับงาน'
            : 'Nearby guards',
        showBack: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: _body(state, ctrl)),
            _ContinueBar(
              enabled: !state.busy && state.guards.isNotEmpty,
              onContinue: () => context.push('/book/payment'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(BookingFlowState state, BookingFlowController ctrl) {
    if (state.busy && state.guards.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null && state.guards.isEmpty) {
      return _ErrorRetry(message: state.error!, onRetry: ctrl.loadGuards);
    }
    if (state.guards.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(PgTokens.space6),
          child: Text(
            'ยังไม่มีเจ้าหน้าที่ว่างในขณะนี้\nNo guards available right now',
            textAlign: TextAlign.center,
            style: TextStyle(color: PgTokens.colorTextMuted),
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(PgTokens.space4),
      children: [
        const _FirstComeBanner(),
        const SizedBox(height: PgTokens.space3),
        for (final guard in state.guards) ...[
          GuardCard(
            guard: guard,
            selected: guard.guardId == state.selectedGuardId,
            onTap: () => ctrl.selectGuard(guard.guardId),
          ),
          const SizedBox(height: PgTokens.space3),
        ],
      ],
    );
  }
}

class _FirstComeBanner extends StatelessWidget {
  const _FirstComeBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(PgTokens.space3),
      decoration: BoxDecoration(
        color: PgTokens.colorSuccessBg,
        borderRadius: BorderRadius.circular(PgTokens.radiusLg),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline, size: 16, color: PgTokens.colorGreen800),
          SizedBox(width: PgTokens.space2),
          Expanded(
            child: Text(
              'เจ้าหน้าที่ที่ว่างจะตอบรับงานของคุณ (first-come) — เลือกคนที่สนใจไว้เพื่อดูเรตติ้งได้',
              style: TextStyle(fontSize: 12, color: PgTokens.colorGreen800),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContinueBar extends StatelessWidget {
  const _ContinueBar({required this.enabled, required this.onContinue});

  final bool enabled;
  final VoidCallback onContinue;

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
          label: 'ดำเนินการชำระเงิน / Continue to payment',
          onPressed: enabled ? onContinue : null,
        ),
      ),
    );
  }
}

class _ErrorRetry extends StatelessWidget {
  const _ErrorRetry({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(PgTokens.space6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined,
                size: 40, color: PgTokens.colorTextMuted),
            const SizedBox(height: PgTokens.space3),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: PgTokens.colorTextMuted)),
            const SizedBox(height: PgTokens.space3),
            PgGhostButton(label: 'ลองใหม่ / Retry', onPressed: onRetry),
          ],
        ),
      ),
    );
  }
}
