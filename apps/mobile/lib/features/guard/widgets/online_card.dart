import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../../core/controllers/tracking_controller.dart';
import '../../../core/network/sockets/presence_socket.dart';

/// The dashboard hero: a deep-forest-green panel with the online/standby toggle and the GPS
/// connection + accuracy readout. Per `Mobile Guard.html` / `Mobile - Active Standby.html`.
class OnlineCard extends ConsumerWidget {
  const OnlineCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(trackingControllerProvider);
    final ctrl = ref.read(trackingControllerProvider.notifier);

    return Container(
      padding: const EdgeInsets.all(PgTokens.space4),
      decoration: BoxDecoration(
        color: PgTokens.colorBrand,
        borderRadius: BorderRadius.circular(PgTokens.radius2xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _StatusText(state: state)),
              Switch(
                value: state.online,
                onChanged: (_) => ctrl.toggle(),
                activeTrackColor: PgTokens.colorAccent,
                activeThumbColor: Colors.white,
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: PgTokens.space3),
            child: Divider(height: 1, color: Colors.white24),
          ),
          _GpsLine(state: state),
        ],
      ),
    );
  }
}

class _StatusText extends StatelessWidget {
  const _StatusText({required this.state});

  final TrackingState state;

  @override
  Widget build(BuildContext context) {
    final String title;
    final String sub;
    if (!state.online) {
      title = 'พร้อมรับงาน / Go online';
      sub = 'คุณกำลังออฟไลน์ · You\'re offline';
    } else if (state.link == PresenceLink.connecting) {
      title = 'กำลังเชื่อมต่อ…';
      sub = 'Connecting to dispatch';
    } else {
      title = 'พร้อมรับงาน / You\'re online';
      sub = 'มองเห็นโดยลูกค้าใกล้เคียง · Visible to customers';
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(
                color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(sub,
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.82), fontSize: 12.5)),
      ],
    );
  }
}

class _GpsLine extends StatelessWidget {
  const _GpsLine({required this.state});

  final TrackingState state;

  @override
  Widget build(BuildContext context) {
    if (!state.online) {
      return Row(
        children: [
          const Icon(Icons.location_off_outlined,
              size: 16, color: Colors.white60),
          const SizedBox(width: PgTokens.space2),
          Text('GPS ปิดอยู่ / tracking off',
              style:
                  TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 13)),
        ],
      );
    }
    if (state.link == PresenceLink.connecting || state.lastSample == null) {
      return const Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
          ),
          SizedBox(width: PgTokens.space2),
          Text('กำลังหาสัญญาณ GPS… / acquiring GPS',
              style: TextStyle(color: Colors.white70, fontSize: 13)),
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
            'GPS เชื่อมต่อแล้ว · ${band.labelTh}',
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
        ),
        if (metres != null)
          Text('${metres.toStringAsFixed(0)} ม.',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700)),
      ],
    );
  }
}
