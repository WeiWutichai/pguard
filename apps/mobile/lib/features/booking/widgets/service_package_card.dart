import 'package:flutter/material.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../../core/models/money.dart';
import '../../../core/models/service_catalog.dart';

/// One bookable-package card from the admin catalog — the shared visual used both by the
/// two-screen picker ([ServiceSelectionScreen], with a radio-dot trailing) and the customer home's
/// "บริการ" list ([CustomerHomeScreen], with a chevron trailing).
///
/// The per-category iconography is gone (the catalog is admin-defined, so there is no fixed icon
/// key) — every card uses the shared brand shield on a tinted tile. Tapping fires [onTap]; the
/// [selected] card gets a brand border + green-50 tint (the picker uses this for its radio
/// selection; the home leaves it `false`). The [trailing] slot lets each host supply its own
/// affordance (radio dot vs. chevron).
class ServicePackageCard extends StatelessWidget {
  const ServicePackageCard({
    super.key,
    required this.service,
    required this.isThai,
    required this.onTap,
    this.selected = false,
    this.trailing,
  });

  final ServiceOption service;
  final bool isThai;
  final VoidCallback onTap;

  /// Selected styling (brand border + green-50 tint + heavier border). Defaults to `false`.
  final bool selected;

  /// Right-side affordance: the picker passes a radio dot; the home passes a chevron. Omitted
  /// (no trailing) when `null`.
  final Widget? trailing;

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
              if (trailing != null) ...[
                const SizedBox(width: PgTokens.space2),
                trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
