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
import 'widgets/service_package_card.dart';

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
            final selected =
                options.any((o) => o.id == _selectedId) ? _selectedId : null;
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
                      // VAT DISCLOSURE, above the prices it qualifies: the catalog's ฿/hr rates
                      // are VAT-EXCLUSIVE, and 7% is added at checkout — so the customer meets
                      // that fact while comparing packages, not as a surprise on the payment
                      // screen (where the tax is itemised as its own line).
                      _VatNote(isThai: isThai),
                      const SizedBox(height: PgTokens.space3),
                      for (final service in options) ...[
                        ServicePackageCard(
                          service: service,
                          isThai: isThai,
                          selected: service.id == selected,
                          onTap: () => setState(() => _selectedId = service.id),
                          trailing: _RadioDot(selected: service.id == selected),
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

/// "ราคายังไม่รวม VAT 7%" — the one honest sentence that keeps the ฿/hr rates on these cards from
/// reading as the whole price. VAT is charged on top of the catalog rate and is itemised on the
/// payment screen; saying so here is cheaper than a surprise at checkout.
class _VatNote extends StatelessWidget {
  const _VatNote({required this.isThai});

  final bool isThai;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(PgTokens.space3),
      decoration: BoxDecoration(
        color: PgTokens.colorSunken,
        borderRadius: BorderRadius.circular(PgTokens.radiusLg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.receipt_long_outlined,
              size: 15, color: PgTokens.colorTextMuted),
          const SizedBox(width: PgTokens.space2),
          Expanded(
            child: Text(
              isThai
                  ? 'ราคาต่อชั่วโมงยังไม่รวมภาษีมูลค่าเพิ่ม ${Money.vatPercent}% '
                      '— ยอดที่ต้องชำระจะแสดง VAT แยกบรรทัดในหน้าชำระเงิน'
                  : 'Hourly rates exclude ${Money.vatPercent}% VAT — the amount you pay shows VAT '
                      'as its own line at checkout.',
              style: const TextStyle(
                  fontSize: 11.5, height: 1.4, color: PgTokens.colorTextMuted),
            ),
          ),
        ],
      ),
    );
  }
}

/// The right-side radio circle (the picker's [ServicePackageCard] trailing): an outline ring when
/// unselected, a filled brand circle with a white check when selected.
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
              isThai ? 'โหลดรายการบริการไม่สำเร็จ' : 'Could not load services',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
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
              style:
                  const TextStyle(fontSize: 15, color: PgTokens.colorTextMuted),
            ),
          ],
        ),
      ),
    );
  }
}
