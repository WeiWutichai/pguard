import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../core/controllers/booking_flow_controller.dart';
import '../../core/models/chat.dart';
import '../../widgets/pguard_header.dart';
import '../../widgets/primary_button.dart';
import '../chat/chat_routes.dart';
import '../notifications/widgets/notification_bell.dart';

/// Customer dashboard (role landing). For this slice it opens the live booking-status screen
/// — the real-time vertical that proves the WS-push pattern. UI per `Mobile - Customer App.html`.
class CustomerHomeScreen extends ConsumerStatefulWidget {
  const CustomerHomeScreen({super.key});

  /// A booking id to track; overridable for demos via `--dart-define=PGUARD_DEMO_BOOKING_ID`.
  static const String _demoBookingId = String.fromEnvironment(
    'PGUARD_DEMO_BOOKING_ID',
    defaultValue: '00000000-0000-0000-0000-000000000001',
  );

  @override
  ConsumerState<CustomerHomeScreen> createState() => _CustomerHomeScreenState();
}

class _CustomerHomeScreenState extends ConsumerState<CustomerHomeScreen> {
  late final TextEditingController _bookingId =
      TextEditingController(text: CustomerHomeScreen._demoBookingId);

  @override
  void dispose() {
    _bookingId.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PGuardHeader(
        title: 'pguard',
        subtitle: 'ลูกค้า · Customer',
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const NotificationBell(),
            IconButton(
              icon: const Icon(Icons.forum_outlined,
                  color: Colors.white, size: 22),
              tooltip: 'แชท / Chat',
              onPressed: () => context.push(ChatRoutes.list(ChatRole.customer)),
            ),
            IconButton(
              icon: const Icon(Icons.person_outline,
                  color: Colors.white, size: 22),
              tooltip: 'โปรไฟล์ / Profile',
              onPressed: () => context.push('/profile'),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(PgTokens.space6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: PgTokens.space4),
              const Text('จองเจ้าหน้าที่รักษาความปลอดภัย',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
              const SizedBox(height: PgTokens.space1),
              const Text(
                'เลือกบริการ ระบุสถานที่ และเรียกเจ้าหน้าที่ใกล้คุณ',
                style: TextStyle(color: PgTokens.colorTextMuted),
              ),
              const SizedBox(height: PgTokens.space4),
              PgPrimaryButton(
                label: 'จองเจ้าหน้าที่ / Book a guard',
                onPressed: () {
                  // Start a fresh draft, then enter the flow.
                  ref.read(bookingFlowControllerProvider.notifier).reset();
                  context.push('/book');
                },
              ),
              const SizedBox(height: PgTokens.space7),
              const Text('ติดตามงานแบบเรียลไทม์',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: PgTokens.space1),
              const Text(
                'สถานะเจ้าหน้าที่อัปเดตสดผ่าน WebSocket (ไม่มีการ polling)',
                style: TextStyle(color: PgTokens.colorTextMuted),
              ),
              const SizedBox(height: PgTokens.space4),
              TextField(
                controller: _bookingId,
                decoration: const InputDecoration(labelText: 'Booking ID'),
              ),
              const SizedBox(height: PgTokens.space4),
              PgPrimaryButton(
                label: 'ติดตามงาน / Track active booking',
                onPressed: () {
                  final id = _bookingId.text.trim();
                  if (id.isNotEmpty) context.push('/booking/$id/live');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
