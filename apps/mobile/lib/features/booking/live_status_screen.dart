import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../core/controllers/booking_status_controller.dart';
import '../../core/models/booking.dart';
import '../../core/network/api_exception.dart';
import '../../widgets/pguard_header.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/status_stepper.dart';

/// THE Phase 2 vertical: the customer's live job screen. It watches the booking-status
/// controller, whose state advances from WebSocket PUSH frames — there is NO `Timer.periodic`
/// polling anywhere in this path (v1 polled every 3–5s; that anti-pattern is gone). UI per
/// `Mobile - Customer App.html` / `Mobile - Active Standby.html`.
class LiveStatusScreen extends ConsumerWidget {
  const LiveStatusScreen({super.key, required this.bookingId});

  final String bookingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(bookingStatusControllerProvider(bookingId));

    return Scaffold(
      appBar: const PGuardHeader(
        title: 'งานดำเนินอยู่',
        subtitle: 'Live job status',
        showBack: true,
        live: true,
        background: PgTokens.colorGreen800,
      ),
      body: SafeArea(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          // Only surface the server's already-generic message; never leak a raw exception
          // toString() (e.g. a parse TypeError) to the user.
          error: (e, _) => _ErrorBody(
            bookingId: bookingId,
            message: e is ApiException
                ? e.message
                : 'ไม่สามารถเชื่อมต่อสถานะงานได้ในขณะนี้',
          ),
          data: (booking) => _LiveBody(booking: booking),
        ),
      ),
    );
  }
}

class _LiveBody extends StatelessWidget {
  const _LiveBody({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(PgTokens.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            decoration: BoxDecoration(
              color: PgTokens.colorSurface,
              borderRadius: BorderRadius.circular(PgTokens.radius2xl),
              border: Border.all(color: PgTokens.colorBorder),
            ),
            padding: const EdgeInsets.all(PgTokens.space4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _GuardCard(booking: booking),
                const SizedBox(height: PgTokens.space4),
                BookingStatusStepper(status: booking.status),
                const SizedBox(height: PgTokens.space4),
                _Actions(booking: booking),
              ],
            ),
          ),
          const SizedBox(height: PgTokens.space4),
          const Row(
            children: [
              Icon(Icons.bolt, size: 16, color: PgTokens.colorPrimary),
              SizedBox(width: PgTokens.space1),
              Expanded(
                child: Text(
                  'อัปเดตสดผ่าน WebSocket — ไม่มีการ polling',
                  style:
                      TextStyle(color: PgTokens.colorTextMuted, fontSize: 12.5),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GuardCard extends StatelessWidget {
  const _GuardCard({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context) {
    final assigned = booking.guardId != null;
    return Row(
      children: [
        CircleAvatar(
          radius: 21,
          backgroundColor: PgTokens.colorGreen100,
          child: Icon(
            assigned ? Icons.shield_outlined : Icons.search,
            color: PgTokens.colorGreen800,
            size: 20,
          ),
        ),
        const SizedBox(width: PgTokens.space3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                assigned
                    ? 'เจ้าหน้าที่รักษาความปลอดภัย'
                    : 'กำลังค้นหาเจ้าหน้าที่',
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              Text(
                booking.address ?? 'pguard',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 12, color: PgTokens.colorTextMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context) {
    final canCancel = !BookingLifecycle.isTerminal(booking.status) &&
        BookingLifecycle.stepIndex(booking.status) <
            BookingLifecycle.stepIndex(BookingStatus.arrived);
    return Row(
      children: [
        _IconAction(icon: Icons.chat_bubble_outline, onTap: () {}),
        const SizedBox(width: PgTokens.space2),
        _IconAction(icon: Icons.call_outlined, onTap: () {}),
        const SizedBox(width: PgTokens.space2),
        Expanded(
          child: PgPrimaryButton(
            label: canCancel ? 'ยกเลิก / Cancel' : 'ดูรายละเอียด / Details',
            color: canCancel ? PgTokens.colorDanger : PgTokens.colorPrimary,
            onPressed: () {},
          ),
        ),
      ],
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: PgTokens.colorSunken,
      borderRadius: BorderRadius.circular(PgTokens.radiusLg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(PgTokens.radiusLg),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, color: PgTokens.colorPrimary, size: 20),
        ),
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.bookingId, required this.message});

  final String bookingId;
  final String message;

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
            const Text(
              'ยังเชื่อมต่อสถานะงานไม่ได้',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: PgTokens.space2),
            Text(
              message,
              textAlign: TextAlign.center,
              style:
                  const TextStyle(color: PgTokens.colorTextMuted, fontSize: 13),
            ),
            const SizedBox(height: PgTokens.space2),
            Text(
              'booking: $bookingId',
              style:
                  const TextStyle(color: PgTokens.colorTextFaint, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
