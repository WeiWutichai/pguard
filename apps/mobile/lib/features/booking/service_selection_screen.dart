import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../core/controllers/booking_flow_controller.dart';
import '../../core/controllers/locale_controller.dart';
import '../../core/models/money.dart';
import '../../core/models/service_catalog.dart';
import '../../widgets/pguard_header.dart';

/// Step 1 of the booking flow — pick a security-service category. Each card shows the
/// indicative ฿/hr estimate (the authoritative `base_fee` is server-owned and arrives on the
/// created booking). UI per `Mobile - Customer App.html` (service-select). The flow is reset to
/// a fresh draft by the home screen's entry button before this screen is pushed.
class ServiceSelectionScreen extends ConsumerWidget {
  const ServiceSelectionScreen({super.key});

  void _pick(WidgetRef ref, BuildContext context, SecurityService service) {
    ref.read(bookingFlowControllerProvider.notifier).selectService(service);
    context.push('/book/form');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    return Scaffold(
      backgroundColor: PgTokens.colorBg,
      appBar: PGuardHeader(
        title: isThai ? 'เลือกประเภทสถานที่' : 'Select place type',
        showBack: true,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(PgTokens.space4),
          children: [
            for (final service in SecurityService.values) ...[
              _ServiceCard(
                service: service,
                isThai: isThai,
                onTap: () => _pick(ref, context, service),
              ),
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
  const _ServiceCard({
    required this.service,
    required this.isThai,
    required this.onTap,
  });

  final SecurityService service;
  final bool isThai;
  final VoidCallback onTap;

  /// Per-service icon treatment from the design (each card is color-coded):
  /// หมู่บ้าน green-900/white · คอนโด green-100/green-700 · โรงงาน amber-100/amber-700 ·
  /// อื่นๆ sunken/muted. (green-700 exact since the full-ramp regen.)
  ({Color bg, Color fg}) get _iconColors {
    switch (service) {
      case SecurityService.village:
        return (bg: PgTokens.colorBrand, fg: Colors.white);
      case SecurityService.condo:
        return (bg: PgTokens.colorGreen100, fg: PgTokens.colorGreen700);
      case SecurityService.factory:
        return (bg: PgTokens.colorAmber100, fg: PgTokens.colorAmber700);
      case SecurityService.other:
        return (bg: PgTokens.colorSunken, fg: PgTokens.colorTextMuted);
    }
  }

  /// Display title — the design's "Other" card carries a parenthetical the catalog id keeps
  /// out of the enum: "อื่นๆ (ระบุเอง)".
  String get _title {
    if (service == SecurityService.other) {
      return isThai ? 'อื่นๆ (ระบุเอง)' : 'Other (custom)';
    }
    return isThai ? service.labelTh : service.labelEn;
  }

  @override
  Widget build(BuildContext context) {
    final estimate = service.indicativeHourlySatang;
    final colors = _iconColors;
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
                  color: colors.bg,
                  borderRadius: BorderRadius.circular(PgTokens.radiusXl),
                ),
                child: Icon(serviceIcon(service), color: colors.fg, size: 24),
              ),
              const SizedBox(width: PgTokens.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _title,
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: PgTokens.colorText),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isThai ? service.descTh : service.descEn,
                      style: const TextStyle(
                          fontSize: 12.5, color: PgTokens.colorTextMuted),
                    ),
                  ],
                ),
              ),
              // Design: exact "฿230/ชม." (monospace 13px muted); the Other card shows NO price.
              if (estimate != null) ...[
                const SizedBox(width: PgTokens.space2),
                Text(
                  isThai
                      ? '${Money.format(estimate)}/ชม.'
                      : '${Money.format(estimate)}/hr',
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
