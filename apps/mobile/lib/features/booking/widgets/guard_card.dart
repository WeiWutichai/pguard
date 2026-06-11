import 'package:flutter/material.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../../core/models/available_guard.dart';

/// One guard in the discovery list. Renders the merged-discovery summary the contract provides
/// — rating average + review count + years of experience (there is no name/avatar/distance in
/// `AvailableGuard`). Selection is a discovery-preview highlight, not an assignment.
class GuardCard extends StatelessWidget {
  const GuardCard({
    super.key,
    required this.guard,
    required this.selected,
    required this.onTap,
  });

  final AvailableGuard guard;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? PgTokens.colorGreen50 : PgTokens.colorSurface,
      borderRadius: BorderRadius.circular(PgTokens.radius2xl),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(PgTokens.radius2xl),
        child: Container(
          padding: const EdgeInsets.all(PgTokens.space3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(PgTokens.radius2xl),
            border: Border.all(
                color: selected
                    ? PgTokens.colorPrimary
                    : PgTokens.colorBorder),
          ),
          child: Row(
            children: [
              // Design avatar: 50×50 rounded square (radius 14) on green-100, 17px w600.
              Container(
                width: 50,
                height: 50,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: PgTokens.colorGreen100,
                  borderRadius: BorderRadius.circular(PgTokens.radiusXl),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    guard.shortHandle,
                    style: const TextStyle(
                        color: PgTokens.colorGreen800,
                        fontWeight: FontWeight.w600,
                        fontSize: 17),
                  ),
                ),
              ),
              const SizedBox(width: PgTokens.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'เจ้าหน้าที่ #${guard.shortHandle}',
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(width: PgTokens.space1),
                        const Icon(Icons.verified,
                            size: 15, color: PgTokens.colorInfo),
                      ],
                    ),
                    const SizedBox(height: 2),
                    _RatingLine(guard: guard),
                  ],
                ),
              ),
              if (selected)
                const Icon(Icons.check_circle, color: PgTokens.colorPrimary)
              else
                const Icon(Icons.radio_button_unchecked,
                    color: PgTokens.colorBorderStrong),
            ],
          ),
        ),
      ),
    );
  }
}

class _RatingLine extends StatelessWidget {
  const _RatingLine({required this.guard});

  final AvailableGuard guard;

  @override
  Widget build(BuildContext context) {
    final parts = <InlineSpan>[];
    if (guard.hasRating) {
      parts.add(const WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Icon(Icons.star, size: 13, color: PgTokens.colorAccent),
      ));
      parts.add(TextSpan(
        text: ' ${guard.rating!.toStringAsFixed(1)} (${guard.reviewCount} รีวิว)',
      ));
    } else {
      parts.add(const TextSpan(text: 'ยังไม่มีรีวิว / No reviews yet'));
    }
    if (guard.yearsOfExperience != null) {
      parts.add(TextSpan(text: ' · ${guard.yearsOfExperience} ปี'));
    }
    return Text.rich(
      TextSpan(
        style: const TextStyle(fontSize: 12.5, color: PgTokens.colorTextMuted),
        children: parts,
      ),
    );
  }
}
