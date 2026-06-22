import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../core/controllers/booking_flow_controller.dart';
import '../../core/controllers/locale_controller.dart';
import '../../core/controllers/services_controller.dart';
import '../../core/models/money.dart';
import '../../core/models/service_catalog.dart';
import '../../widgets/pguard_header.dart';
import '../../widgets/primary_button.dart';

/// Step 1 of the booking flow — pick a service from the ADMIN-DEFINED catalog
/// (`GET /v1/services`). Each card shows the indicative ฿/hr estimate + the admin's min-hours
/// (the authoritative `base_fee`/`min_hours` are server-owned and applied on the created
/// booking). The flow is reset to a fresh draft by the home screen's entry button before this
/// screen is pushed.
class ServiceSelectionScreen extends ConsumerWidget {
  const ServiceSelectionScreen({super.key});

  void _pick(WidgetRef ref, BuildContext context, ServiceOption service) {
    ref.read(bookingFlowControllerProvider.notifier).selectService(service);
    context.push('/book/form');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    final services = ref.watch(servicesProvider);
    return Scaffold(
      backgroundColor: PgTokens.colorBg,
      appBar: PGuardHeader(
        light: true,
        title: isThai ? 'เลือกประเภทบริการ' : 'Select a service',
        showBack: true,
      ),
      body: SafeArea(
        child: services.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => _ErrorState(
            isThai: isThai,
            onRetry: () => ref.invalidate(servicesProvider),
          ),
          data: (options) {
            if (options.isEmpty) return _EmptyState(isThai: isThai);
            return ListView(
              padding: const EdgeInsets.all(PgTokens.space4),
              children: [
                for (final service in options) ...[
                  _ServiceCard(
                    service: service,
                    isThai: isThai,
                    onTap: () => _pick(ref, context, service),
                  ),
                  const SizedBox(height: PgTokens.space3),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

/// One bookable-service card. The per-category iconography is gone (the catalog is admin-defined,
/// so there is no fixed icon key) — every card uses the shared brand shield.
class _ServiceCard extends StatelessWidget {
  const _ServiceCard({
    required this.service,
    required this.isThai,
    required this.onTap,
  });

  final ServiceOption service;
  final bool isThai;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasEstimate = service.baseFeeSatang > 0;
    return Material(
      color: PgTokens.colorSurface,
      borderRadius: BorderRadius.circular(PgTokens.radius2xl),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(PgTokens.radius2xl),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(PgTokens.radius2xl),
            border: Border.all(color: PgTokens.colorBorder, width: 1.5),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: PgTokens.colorBrand,
                  borderRadius: BorderRadius.circular(PgTokens.radiusXl),
                ),
                child: const Icon(Icons.shield_outlined,
                    color: Colors.white, size: 24),
              ),
              const SizedBox(width: PgTokens.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      service.name(isThai),
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: PgTokens.colorText),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isThai
                          ? 'ขั้นต่ำ ${service.minHours} ชม.'
                          : 'Min. ${service.minHours} hr',
                      style: const TextStyle(
                          fontSize: 12.5, color: PgTokens.colorTextMuted),
                    ),
                  ],
                ),
              ),
              // Indicative "฿230/ชม." (monospace, muted); shown only when the catalog gives a fee.
              if (hasEstimate) ...[
                const SizedBox(width: PgTokens.space2),
                Text(
                  isThai
                      ? '${Money.format(service.baseFeeSatang)}/ชม.'
                      : '${Money.format(service.baseFeeSatang)}/hr',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 13,
                    color: PgTokens.colorTextMuted,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Catalog fetch failed — message + retry (re-fetches `GET /v1/services`).
class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.isThai, required this.onRetry});

  final bool isThai;
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
            Text(
              isThai
                  ? 'โหลดรายการบริการไม่สำเร็จ'
                  : 'Could not load services',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: PgTokens.space4),
            PgPrimaryButton(
              label: isThai ? 'ลองอีกครั้ง' : 'Try again',
              onPressed: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}

/// The active catalog is empty (admin has published none).
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.isThai});

  final bool isThai;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(PgTokens.space6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.inbox_outlined,
                size: 40, color: PgTokens.colorTextMuted),
            const SizedBox(height: PgTokens.space3),
            Text(
              isThai
                  ? 'ยังไม่มีบริการให้เลือกในขณะนี้'
                  : 'No services available right now',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 15, color: PgTokens.colorTextMuted),
            ),
          ],
        ),
      ),
    );
  }
}
