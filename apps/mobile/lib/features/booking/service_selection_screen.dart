import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../core/controllers/locale_controller.dart';
import '../../core/controllers/services_controller.dart';
import '../../core/models/money.dart';
import '../../core/models/service_catalog.dart';
import '../../widgets/pguard_header.dart';
import '../../widgets/primary_button.dart';

/// Step 1 of the booking flow — pick a package from the ADMIN-DEFINED catalog
/// (`GET /v1/services`). This is the first of a two-screen "package picker": here the customer
/// RADIO-SELECTS one service (local state, no navigation), then taps "ดูรายละเอียด" to open the
/// detail screen. Each card shows the indicative ฿/hr estimate + the admin's min-hours (the
/// authoritative `base_fee`/`min_hours` are server-owned and applied on the created booking). The
/// flow is reset to a fresh draft by the home screen's entry button before this screen is pushed.
class ServiceSelectionScreen extends ConsumerStatefulWidget {
  const ServiceSelectionScreen({super.key});

  @override
  ConsumerState<ServiceSelectionScreen> createState() =>
      _ServiceSelectionScreenState();
}

class _ServiceSelectionScreenState
    extends ConsumerState<ServiceSelectionScreen> {
  /// The radio-selected service id (local UI state — does NOT touch the booking flow until the
  /// customer confirms on the detail screen).
  String? _selectedId;

  void _viewDetails(ServiceOption service) {
    // Pass the chosen ServiceOption to the detail screen via go_router `extra` (the detail screen
    // also falls back to a servicesProvider lookup by id for deep links — see service_detail).
    context.push('/book/detail', extra: service);
  }

  @override
  Widget build(BuildContext context) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    final services = ref.watch(servicesProvider);
    return Scaffold(
      backgroundColor: PgTokens.colorBg,
      appBar: PGuardHeader(
        light: true,
        title: isThai ? 'เลือกแพ็กเกจบริการ' : 'Choose a package',
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
            // Drop a stale selection if the catalog changed under us (e.g. retry returned a
            // different set), so the bottom CTA can't carry a no-longer-present id.
            final selected = options.any((o) => o.id == _selectedId)
                ? _selectedId
                : null;
            return Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(PgTokens.space4),
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(
                            left: PgTokens.space1, bottom: PgTokens.space2),
                        child: Text(
                          isThai ? 'ประเภทสถานที่' : 'Place type',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: PgTokens.colorTextMuted,
                          ),
                        ),
                      ),
                      for (final service in options) ...[
                        _ServiceCard(
                          service: service,
                          isThai: isThai,
                          selected: service.id == selected,
                          onTap: () =>
                              setState(() => _selectedId = service.id),
                        ),
                        const SizedBox(height: PgTokens.space3),
                      ],
                    ],
                  ),
                ),
                _SelectionFooter(
                  isThai: isThai,
                  // Disabled until a package is radio-selected.
                  onPressed: selected == null
                      ? null
                      : () => _viewDetails(
                          options.firstWhere((o) => o.id == selected)),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// One bookable-package card with a RADIO control. The per-category iconography is gone (the
/// catalog is admin-defined, so there is no fixed icon key) — every card uses the shared brand
/// shield on a tinted tile. Tapping selects it; the SELECTED card gets a brand border + tint and a
/// filled radio with a white check.
class _ServiceCard extends StatelessWidget {
  const _ServiceCard({
    required this.service,
    required this.isThai,
    required this.selected,
    required this.onTap,
  });

  final ServiceOption service;
  final bool isThai;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasEstimate = service.baseFeeSatang > 0;
    final description = service.description;
    return Material(
      color: selected ? PgTokens.colorGreen50 : PgTokens.colorSurface,
      borderRadius: BorderRadius.circular(PgTokens.radius2xl),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(PgTokens.radius2xl),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(PgTokens.radius2xl),
            border: Border.all(
              color: selected ? PgTokens.colorPrimary : PgTokens.colorBorder,
              width: selected ? 2 : 1.5,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left rounded-square icon on a tinted tile (shared shield — no per-service icon).
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: PgTokens.colorGreen50,
                  borderRadius: BorderRadius.circular(PgTokens.radiusXl),
                ),
                child: const Icon(Icons.shield_outlined,
                    color: PgTokens.colorBrand, size: 24),
              ),
              const SizedBox(width: PgTokens.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // The design shows a "ยอดนิยม"/Popular badge here — OMITTED: there's no
                    // popularity data and we won't fabricate one. Restore once the backend
                    // catalog carries a popularity flag.
                    Text(
                      service.name(isThai),
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: PgTokens.colorText),
                    ),
                    // Customer-facing blurb (muted). Omitted entirely when the catalog has none.
                    if (description != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        description,
                        style: const TextStyle(
                            fontSize: 12.5,
                            height: 1.35,
                            color: PgTokens.colorTextMuted),
                      ),
                    ],
                    const SizedBox(height: 6),
                    // "฿230 /ชม." indicative rate (shown only when the catalog gives a fee)…
                    if (hasEstimate)
                      Text(
                        isThai
                            ? '${Money.format(service.baseFeeSatang)} /ชม.'
                            : '${Money.format(service.baseFeeSatang)} /hr',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: PgTokens.colorText,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    // …with a faint min-hours line under it.
                    Text(
                      isThai
                          ? 'ขั้นต่ำ ${service.minHours} ชม.'
                          : 'Min. ${service.minHours} hr',
                      style: const TextStyle(
                          fontSize: 12, color: PgTokens.colorTextFaint),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: PgTokens.space2),
              _RadioDot(selected: selected),
            ],
          ),
        ),
      ),
    );
  }
}

/// The right-side radio circle: an outline ring when unselected, a filled brand circle with a
/// white check when selected.
class _RadioDot extends StatelessWidget {
  const _RadioDot({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? PgTokens.colorPrimary : Colors.transparent,
        border: Border.all(
          color: selected ? PgTokens.colorPrimary : PgTokens.colorBorderStrong,
          width: 2,
        ),
      ),
      child: selected
          ? const Icon(Icons.check, size: 15, color: Colors.white)
          : null,
    );
  }
}

/// Sticky bottom footer: a full-width "ดูรายละเอียด" CTA, disabled until a package is selected.
class _SelectionFooter extends StatelessWidget {
  const _SelectionFooter({required this.isThai, this.onPressed});

  final bool isThai;
  final VoidCallback? onPressed;

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
          label: isThai ? 'ดูรายละเอียด' : 'View details',
          onPressed: onPressed,
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
