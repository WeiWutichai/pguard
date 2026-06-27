import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../../core/controllers/guard_jobs_controller.dart';
import '../../../core/controllers/locale_controller.dart';
import '../../../core/controllers/tracking_controller.dart';
import '../../../core/models/booking.dart';
import '../../../core/network/sockets/presence_socket.dart';
import '../../../core/permissions/permission_gate.dart';
import '../../../core/providers.dart';

/// The dashboard hero: a deep-forest-green panel with the online/standby toggle and the GPS
/// connection + accuracy readout. Per `Mobile Guard.html` / `Mobile - Active Standby.html`.
class OnlineCard extends ConsumerWidget {
  const OnlineCard({super.key});

  /// Going OFFLINE needs no permission. Going ONLINE makes the guard GPS-trackable, so show the
  /// location rationale first if it isn't granted yet (honest pre-prompt) — then go online
  /// regardless: the presence socket works without a live fix (the GPS source is still stubbed
  /// and degrades gracefully). Once geolocator lands, a denied permission will actually matter.
  Future<void> _onToggle(
      BuildContext context, WidgetRef ref, TrackingState state) async {
    final ctrl = ref.read(trackingControllerProvider.notifier);
    if (state.online) {
      ctrl.toggle();
      return;
    }
    final status = await ref.read(permissionGateProvider).locationStatus();
    if (status != PgPermissionState.granted && context.mounted) {
      await context.push('/permissions/location', extra: true);
    }
    // Don't go online if the guard navigated away during the rationale.
    if (!context.mounted) return;
    ctrl.toggle();
  }

  /// #123 — whether the guard currently HAS a job in hand (accepted / en_route / arrived /
  /// pending_completion). Drives the distinct "busy" toggle state so the panel signals the guard is
  /// occupied rather than just "online & idle". Reuses [GuardJobsController.active] (the SAME
  /// partition the My-Jobs list uses) over the cached jobs feed — best-effort: a loading / failed
  /// feed reports `false` (fall back to the normal online/offline states, never a wrong "busy").
  static bool hasActiveJob(List<Booking>? jobs) =>
      jobs != null && GuardJobsController.active(jobs).isNotEmpty;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    final state = ref.watch(trackingControllerProvider);
    // The guard's cached jobs feed — same source the dashboard list reads. `onJob` only matters
    // while ONLINE: an offline guard with a lingering active job still shows the offline state
    // (the toggle's job is to convey availability; "busy" is an online sub-state).
    final onJob = state.online &&
        hasActiveJob(ref.watch(guardJobsControllerProvider).valueOrNull);

    return Container(
      // Design hero `.online-card`: 20px padding + 20px corners.
      padding: const EdgeInsets.all(PgTokens.space5),
      decoration: BoxDecoration(
        // Deep-forest panel with a subtle atmospheric glow in the top-right corner (design
        // `.online-card` — a lighter spot fading into the brand) via a radial gradient, plus a
        // soft small elevation (--sh-sm).
        gradient: const RadialGradient(
          center: Alignment(0.95, -0.95),
          radius: 1.2,
          colors: [PgTokens.colorGreen700, PgTokens.colorBrand],
          stops: [0.0, 0.65],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                  child:
                      _StatusText(state: state, isThai: isThai, onJob: onJob)),
              Switch(
                value: state.online,
                onChanged: (_) => _onToggle(context, ref, state),
                activeTrackColor: PgTokens.colorAccent,
                activeThumbColor: Colors.white,
              ),
            ],
          ),
          // Design `.gps-line`: a faint 18%-white hairline with asymmetric 18/16 spacing.
          Padding(
            padding: const EdgeInsets.only(top: 18, bottom: 16),
            child:
                Container(height: 1, color: Colors.white.withValues(alpha: 0.18)),
          ),
          _GpsLine(state: state, isThai: isThai),
        ],
      ),
    );
  }
}

class _StatusText extends StatelessWidget {
  const _StatusText(
      {required this.state, required this.isThai, this.onJob = false});

  final TrackingState state;
  final bool isThai;

  /// #123 — the guard is ONLINE *and* has a job in hand. Renders the distinct "busy" treatment
  /// (an amber "กำลังดำเนินงานอยู่ / On a job" pill + busy copy) so the toggle area no longer reads
  /// as a plain idle-green "online" while the guard is actually working a job.
  final bool onJob;

  @override
  Widget build(BuildContext context) {
    // BUSY: online with an active job — a clearly DIFFERENT (amber) signal, not the idle green.
    if (onJob) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Amber pill — the "different color" the busy state must show (vs. the online green).
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: PgTokens.colorAccent,
              borderRadius: BorderRadius.circular(PgTokens.radiusFull),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.work_outline,
                    size: 13, color: PgTokens.colorOnAmber),
                const SizedBox(width: 4),
                Text(
                  isThai ? 'กำลังดำเนินงานอยู่' : 'On a job',
                  style: const TextStyle(
                    color: PgTokens.colorOnAmber,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(isThai ? 'กำลังดำเนินงานอยู่' : 'On a job',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  height: 1.1,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            isThai ? 'ไม่รับงานใหม่ระหว่างทำงาน' : 'Not taking new jobs',
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.82), fontSize: 12.5),
          ),
        ],
      );
    }
    final String title;
    final String sub;
    if (!state.online) {
      title = isThai ? 'พร้อมรับงาน' : 'Go online';
      sub = isThai ? 'คุณกำลังออฟไลน์' : "You're offline";
    } else if (state.link == PresenceLink.connecting) {
      title = isThai ? 'กำลังเชื่อมต่อ…' : 'Connecting…';
      sub = isThai ? 'กำลังเชื่อมต่อระบบจ่ายงาน' : 'Connecting to dispatch';
    } else {
      title = isThai ? 'พร้อมรับงาน' : "You're online";
      sub =
          isThai ? 'มองเห็นโดยลูกค้าใกล้เคียง' : 'Visible to nearby customers';
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                height: 1.1,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(sub,
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.82), fontSize: 12.5)),
      ],
    );
  }
}

class _GpsLine extends StatelessWidget {
  const _GpsLine({required this.state, required this.isThai});

  final TrackingState state;
  final bool isThai;

  @override
  Widget build(BuildContext context) {
    if (!state.online) {
      return Row(
        children: [
          const Icon(Icons.location_off_outlined,
              size: 16, color: Colors.white60),
          const SizedBox(width: PgTokens.space2),
          Text(isThai ? 'GPS ปิดอยู่' : 'Tracking off',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7), fontSize: 13)),
        ],
      );
    }
    if (state.link == PresenceLink.connecting || state.lastSample == null) {
      return Row(
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: Colors.white70),
          ),
          const SizedBox(width: PgTokens.space2),
          Text(isThai ? 'กำลังหาสัญญาณ GPS…' : 'Acquiring GPS…',
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
        ],
      );
    }
    final band = state.accuracyBand;
    final metres = state.lastSample!.accuracy;
    return Row(
      children: [
        const Icon(Icons.gps_fixed, size: 16, color: Colors.white),
        const SizedBox(width: PgTokens.space2),
        Expanded(
          child: Text(
            isThai
                ? 'GPS เชื่อมต่อแล้ว · ${band.labelTh}'
                : 'GPS connected · ${band.labelEn}',
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
        ),
        if (metres != null)
          // Design accuracy readout: mono w600 numerals.
          Text(
              isThai
                  ? '${metres.toStringAsFixed(0)} ม.'
                  : '${metres.toStringAsFixed(0)} m',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'IBMPlexMono',
                  fontFeatures: [FontFeature.tabularFigures()])),
      ],
    );
  }
}
