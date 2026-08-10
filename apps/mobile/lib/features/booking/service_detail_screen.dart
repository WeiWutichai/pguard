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

/// Step 1b of the booking flow — the package DETAIL screen (the second of the two-screen package
/// picker). Reached from [ServiceSelectionScreen] after the customer radio-selects a package and
/// taps "ดูรายละเอียด". Shows a brand hero, the platform's static "included" guarantees, and a
/// pricing breakdown derived from the catalog's indicative `base_fee × min_hours`. The estimate is
/// DISPLAY ONLY — the server owns the authoritative rate on the created booking. Confirming
/// commits the selection to the shared [BookingFlowController] and advances to the booking form.
class ServiceDetailScreen extends ConsumerWidget {
  const ServiceDetailScreen({super.key, required this.service});

  /// The selected package, passed via go_router `extra` from the selection screen.
  final ServiceOption service;

  void _choose(WidgetRef ref, BuildContext context) {
    ref.read(bookingFlowControllerProvider.notifier).selectService(service);
    // Reuse the existing booking-form route (the gate: a package must be chosen before the form).
    context.push('/book/form');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    final hasEstimate = service.baseFeeSatang > 0;
    // Starting price = indicative ฿/hr × min-hours, in exact satang (Money, never a float).
    final startingSatang = service.baseFeeSatang * service.minHours;
    return Scaffold(
      backgroundColor: PgTokens.colorBg,
      appBar: PGuardHeader(
        light: true,
        title: service.name(isThai),
        showBack: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(PgTokens.space4),
                children: [
                  _HeroCard(service: service, isThai: isThai),
                  const SizedBox(height: PgTokens.space5),
                  _SectionLabel(text: isThai ? 'รวมในแพ็กเกจ' : 'Included'),
                  const SizedBox(height: PgTokens.space3),
                  _IncludedList(isThai: isThai),
                  const SizedBox(height: PgTokens.space5),
                  _PricingCard(
                    isThai: isThai,
                    hasEstimate: hasEstimate,
                    baseFeeSatang: service.baseFeeSatang,
                    minHours: service.minHours,
                    startingSatang: startingSatang,
                  ),
                ],
              ),
            ),
            _ChooseFooter(
              isThai: isThai,
              onPressed: () => _choose(ref, context),
            ),
          ],
        ),
      ),
    );
  }
}

/// Deep-brand-green hero: a lighter rounded-square icon tile + the name (white) + the blurb.
class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.service, required this.isThai});

  final ServiceOption service;
  final bool isThai;

  @override
  Widget build(BuildContext context) {
    final description = service.description;
    return Container(
      padding: const EdgeInsets.all(PgTokens.space5),
      decoration: BoxDecoration(
        color: PgTokens.colorBrand,
        borderRadius: BorderRadius.circular(PgTokens.radius2xl),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              // A lighter tile against the deep-green hero.
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(PgTokens.radiusXl),
            ),
            child: const Icon(Icons.shield_outlined,
                color: Colors.white, size: 26),
          ),
          const SizedBox(width: PgTokens.space4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  service.name(isThai),
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                if (description != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.45,
                      color: Colors.white.withValues(alpha: 0.82),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: PgTokens.space1),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: PgTokens.colorTextMuted,
        ),
      ),
    );
  }
}

/// The STATIC "included" checklist — these are platform-wide guarantees, identical for every
/// package, so they are hardcoded (not driven by the catalog).
class _IncludedList extends StatelessWidget {
  const _IncludedList({required this.isThai});

  final bool isThai;

  @override
  Widget build(BuildContext context) {
    final rows = isThai
        ? const [
            ('ตรวจรอบรายชั่วโมง + รูปยืนยัน', 'เช็คอินพร้อม GPS ทุกชั่วโมง'),
            ('ติดตามตำแหน่งแบบเรียลไทม์', 'ดูตำแหน่งเจ้าหน้าที่บนแผนที่'),
            ('แชต & โทรในแอป', 'ติดต่อเจ้าหน้าที่ได้ตลอดงาน'),
          ]
        : const [
            ('Hourly patrol + photo proof', 'GPS check-in every hour'),
            ('Real-time tracking', 'See the guard on the map'),
            ('In-app chat & call', 'Reach the guard anytime'),
          ];
    return Container(
      decoration: BoxDecoration(
        color: PgTokens.colorSurface,
        borderRadius: BorderRadius.circular(PgTokens.radius2xl),
        border: Border.all(color: PgTokens.colorBorder),
      ),
      padding: const EdgeInsets.symmetric(
          horizontal: PgTokens.space4, vertical: PgTokens.space2),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: PgTokens.colorBorder),
            _IncludedRow(title: rows[i].$1, subtitle: rows[i].$2),
          ],
        ],
      ),
    );
  }
}

class _IncludedRow extends StatelessWidget {
  const _IncludedRow({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: PgTokens.space3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: PgTokens.colorSuccessBg,
              borderRadius: BorderRadius.circular(PgTokens.radiusMd),
            ),
            child: const Icon(Icons.check_circle,
                size: 18, color: PgTokens.colorSuccess),
          ),
          const SizedBox(width: PgTokens.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: PgTokens.colorText,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  style: const TextStyle(
                      fontSize: 12.5, color: PgTokens.colorTextMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Pricing breakdown: base rate, min-hours, divider, the "เริ่มต้น" starting figure
/// (base × min, brand-green) and the actual-time footnote.
class _PricingCard extends StatelessWidget {
  const _PricingCard({
    required this.isThai,
    required this.hasEstimate,
    required this.baseFeeSatang,
    required this.minHours,
    required this.startingSatang,
  });

  final bool isThai;
  final bool hasEstimate;
  final int baseFeeSatang;
  final int minHours;
  final int startingSatang;

  @override
  Widget build(BuildContext context) {
    // Catalog rates are VAT-EXCLUSIVE, so the "เริ่มต้น" figure a customer reads as the price must
    // carry the 7% they will actually be charged — with the tax on its own row above it.
    final vatSatang = Money.vat(startingSatang);
    final startingWithVatSatang = startingSatang + vatSatang;
    return Container(
      decoration: BoxDecoration(
        color: PgTokens.colorSurface,
        borderRadius: BorderRadius.circular(PgTokens.radius2xl),
        border: Border.all(color: PgTokens.colorBorder),
      ),
      padding: const EdgeInsets.all(PgTokens.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PriceRow(
            label: isThai ? 'ค่าบริการพื้นฐาน' : 'Base rate',
            value: hasEstimate
                ? (isThai
                    ? '${Money.format(baseFeeSatang)} /ชม.'
                    : '${Money.format(baseFeeSatang)} /hr')
                : '—',
          ),
          const SizedBox(height: PgTokens.space2),
          _PriceRow(
            label: isThai ? 'ชั่วโมงขั้นต่ำ' : 'Minimum hours',
            value: isThai ? '$minHours ชม.' : '$minHours hr',
          ),
          if (hasEstimate) ...[
            const SizedBox(height: PgTokens.space2),
            _PriceRow(
              label: isThai
                  ? 'ภาษีมูลค่าเพิ่ม ${Money.vatPercent}%'
                  : 'VAT ${Money.vatPercent}%',
              value: Money.format(vatSatang),
            ),
          ],
          const Padding(
            padding: EdgeInsets.symmetric(vertical: PgTokens.space3),
            child: Divider(height: 1, color: PgTokens.colorBorder),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                isThai ? 'เริ่มต้น' : 'Starting at',
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              Text(
                hasEstimate ? Money.format(startingWithVatSatang) : '—',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: PgTokens.colorPrimary,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          if (hasEstimate) ...[
            const SizedBox(height: PgTokens.space2),
            Text(
              isThai
                  ? '${Money.format(baseFeeSatang)} × $minHours ชม. + VAT ${Money.vatPercent}% · ยอดจริงคำนวณตามเวลาทำงานจริง'
                  : '${Money.format(baseFeeSatang)} × $minHours hr + ${Money.vatPercent}% VAT · final total is billed by actual time',
              style: const TextStyle(
                  fontSize: 11.5, height: 1.4, color: PgTokens.colorTextFaint),
            ),
          ],
        ],
      ),
    );
  }
}

class _PriceRow extends StatelessWidget {
  const _PriceRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style:
                const TextStyle(fontSize: 14, color: PgTokens.colorTextMuted)),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: PgTokens.colorText,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// Sticky bottom footer: a full-width "เลือกแพ็กเกจนี้" CTA that commits the selection + advances.
class _ChooseFooter extends StatelessWidget {
  const _ChooseFooter({required this.isThai, required this.onPressed});

  final bool isThai;
  final VoidCallback onPressed;

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
          label: isThai ? 'เลือกแพ็กเกจนี้' : 'Choose this package',
          onPressed: onPressed,
        ),
      ),
    );
  }
}

/// Deep-link fallback for `/book/detail?id=<svc>` (no `extra`): looks the service up in the live
/// catalog (`servicesProvider`) and renders [ServiceDetailScreen]. Within the normal flow the
/// ServiceOption rides in `extra`, so this only runs for cold deep links. Shows a spinner while the
/// catalog loads and a not-found message if the id is unknown.
class ServiceDetailResolver extends ConsumerWidget {
  const ServiceDetailResolver({super.key, required this.serviceId});

  final String? serviceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    final services = ref.watch(servicesProvider);
    return services.when(
      loading: () => const Scaffold(
        backgroundColor: PgTokens.colorBg,
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => _resolverMessage(
          isThai ? 'โหลดข้อมูลไม่สำเร็จ' : 'Could not load this package'),
      data: (options) {
        ServiceOption? match;
        for (final o in options) {
          if (o.id == serviceId) {
            match = o;
            break;
          }
        }
        if (match == null) {
          return _resolverMessage(
              isThai ? 'ไม่พบแพ็กเกจนี้' : 'Package not found');
        }
        return ServiceDetailScreen(service: match);
      },
    );
  }

  Widget _resolverMessage(String text) => Scaffold(
        backgroundColor: PgTokens.colorBg,
        appBar: PGuardHeader(light: true, title: text, showBack: true),
        body: Center(
          child: Text(text,
              style: const TextStyle(color: PgTokens.colorTextMuted)),
        ),
      );
}
