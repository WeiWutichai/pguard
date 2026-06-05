import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../core/controllers/booking_flow_controller.dart';
import '../../core/models/money.dart';
import '../../core/models/service_catalog.dart';
import '../../widgets/pguard_header.dart';

/// Step 1 of the booking flow — pick a security-service category. Each card shows the
/// indicative ฿/hr estimate (the authoritative `base_fee` is server-owned and arrives on the
/// created booking). UI per `Mobile - Customer App.html` (service-select). Entering this screen
/// resets the flow so every booking starts fresh.
class ServiceSelectionScreen extends ConsumerStatefulWidget {
  const ServiceSelectionScreen({super.key});

  @override
  ConsumerState<ServiceSelectionScreen> createState() =>
      _ServiceSelectionScreenState();
}

class _ServiceSelectionScreenState
    extends ConsumerState<ServiceSelectionScreen> {
  @override
  void initState() {
    super.initState();
    // Fresh draft on flow entry (the controller is keepAlive across the five screens).
    // Deferred off the build phase — modifying a provider during initState is disallowed.
    Future.microtask(() {
      if (mounted) ref.read(bookingFlowControllerProvider.notifier).reset();
    });
  }

  void _pick(SecurityService service) {
    ref.read(bookingFlowControllerProvider.notifier).selectService(service);
    context.push('/book/form');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PgTokens.colorBg,
      appBar: const PGuardHeader(
        title: 'เลือกประเภทสถานที่',
        subtitle: 'Select place type',
        showBack: true,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(PgTokens.space4),
          children: [
            for (final service in SecurityService.values) ...[
              _ServiceCard(service: service, onTap: () => _pick(service)),
              const SizedBox(height: PgTokens.space3),
            ],
          ],
        ),
      ),
    );
  }
}

/// Maps a service category to its card icon (icons live in the widget layer, not the model).
IconData serviceIcon(SecurityService service) {
  switch (service) {
    case SecurityService.village:
      return Icons.holiday_village_outlined;
    case SecurityService.condo:
      return Icons.apartment_outlined;
    case SecurityService.factory:
      return Icons.factory_outlined;
    case SecurityService.other:
      return Icons.add_circle_outline;
  }
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({required this.service, required this.onTap});

  final SecurityService service;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final estimate = service.indicativeHourlySatang;
    return Material(
      color: PgTokens.colorSurface,
      borderRadius: BorderRadius.circular(PgTokens.radius2xl),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(PgTokens.radius2xl),
        child: Container(
          padding: const EdgeInsets.all(PgTokens.space4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(PgTokens.radius2xl),
            border: Border.all(color: PgTokens.colorBorder),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: PgTokens.colorGreen50,
                  borderRadius: BorderRadius.circular(PgTokens.radiusLg),
                ),
                child: Icon(serviceIcon(service),
                    color: PgTokens.colorGreen800, size: 24),
              ),
              const SizedBox(width: PgTokens.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${service.labelTh} · ${service.labelEn}',
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: PgTokens.colorText),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${service.descTh} / ${service.descEn}',
                      style: const TextStyle(
                          fontSize: 12.5, color: PgTokens.colorTextMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: PgTokens.space2),
              Text(
                estimate != null
                    ? 'เริ่ม ${Money.format(estimate)}/ชม.'
                    : 'ตามจริง',
                textAlign: TextAlign.right,
                style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: PgTokens.colorTextMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
