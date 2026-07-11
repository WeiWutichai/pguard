import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../../core/controllers/locale_controller.dart';
import '../../../core/models/available_guard.dart';

/// One guard in the discovery list. Renders the guard's REAL NAME + PHOTO when discovery provides
/// them (falling back to an id handle + initials avatar otherwise), plus the rating summary
/// (average + review count + years of experience). Selection is a discovery-preview highlight,
/// not an assignment (first-come).
class GuardCard extends ConsumerWidget {
  const GuardCard({
    super.key,
    required this.guard,
    required this.selected,
    required this.onTap,
    required this.onViewReviews,
  });

  final AvailableGuard guard;
  final bool selected;

  /// Tapping the card body radio-SELECTS this guard (first-come preference highlight).
  final VoidCallback onTap;

  /// Opens this guard's reviews — a DISTINCT affordance (the "ดูรีวิว / View reviews" button) so
  /// viewing reviews never radio-selects the guard.
  final VoidCallback onViewReviews;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
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
                color: selected ? PgTokens.colorPrimary : PgTokens.colorBorder),
          ),
          child: Row(
            children: [
              // Design avatar: 50×50 rounded square (radius 14). Shows the guard's PHOTO when the
              // discovery list provides an avatar URL; falls back to the initials monogram on
              // green-100 when there is no photo (or the image fails to load).
              _GuardAvatar(guard: guard),
              const SizedBox(width: PgTokens.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            // REAL NAME when discovery provides it, else the "เจ้าหน้าที่ #XXXX"
                            // id handle (forward-compatible with the un-enriched contract).
                            guard.displayLabel(isThai),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600),
                          ),
                        ),
                        const SizedBox(width: PgTokens.space1),
                        const Icon(Icons.verified,
                            size: 15, color: PgTokens.colorInfo),
                      ],
                    ),
                    const SizedBox(height: 2),
                    _RatingLine(guard: guard),
                    const SizedBox(height: 4),
                    // Distinct, compact "ดูรีวิว / View reviews" affordance. Its own InkWell
                    // stops the tap from bubbling to the card body (which radio-selects), so
                    // viewing reviews never changes the first-come selection.
                    _ViewReviewsButton(onTap: onViewReviews),
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

/// The 50×50 rounded-square avatar: the guard's profile PHOTO when discovery provides an
/// `avatar_url`, else the initials monogram on green-100. The image decodes into the same rounded
/// frame and falls back to the monogram if it errors (a stale presigned URL or a dead link never
/// leaves an empty box).
class _GuardAvatar extends StatelessWidget {
  const _GuardAvatar({required this.guard});

  final AvailableGuard guard;

  @override
  Widget build(BuildContext context) {
    final monogram = FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        guard.avatarInitials,
        style: const TextStyle(
            color: PgTokens.colorGreen800,
            fontWeight: FontWeight.w600,
            fontSize: 17),
      ),
    );
    return Container(
      width: 50,
      height: 50,
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: PgTokens.colorGreen100,
        borderRadius: BorderRadius.circular(PgTokens.radiusXl),
      ),
      child: guard.hasPhoto
          ? Image.network(
              guard.avatarUrl!,
              width: 50,
              height: 50,
              fit: BoxFit.cover,
              // Keep the monogram visible behind the image until it decodes (no flash of empty
              // box), and restore it if the URL fails to load.
              loadingBuilder: (context, child, progress) =>
                  progress == null ? child : monogram,
              errorBuilder: (context, _, __) => monogram,
            )
          : monogram,
    );
  }
}

class _RatingLine extends ConsumerWidget {
  const _RatingLine({required this.guard});

  final AvailableGuard guard;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    final parts = <InlineSpan>[];
    if (guard.hasRating) {
      parts.add(const WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Icon(Icons.star, size: 13, color: PgTokens.colorAccent),
      ));
      parts.add(TextSpan(
        text:
            ' ${guard.rating!.toStringAsFixed(1)} (${guard.reviewCount} รีวิว)',
      ));
    } else {
      parts.add(TextSpan(text: isThai ? 'ยังไม่มีรีวิว' : 'No reviews yet'));
    }
    if (guard.yearsOfExperience != null) {
      parts.add(TextSpan(text: ' · ${guard.yearsOfExperience} ปี'));
    }
    // Documents indicator — WHETHER the guard's credential documents are on file, never the
    // documents themselves (wire-driven `has_documents`, unlike the static verified badge in
    // the title row). Tri-state: true/false both render (an honest absence), but UNKNOWN (an
    // older backend that omitted the field) renders nothing — never a false "no documents".
    if (guard.hasDocuments case final hasDocs?) {
      parts.add(TextSpan(
        text: hasDocs
            ? (isThai ? ' · มีเอกสาร' : ' · Docs on file')
            : (isThai ? ' · ไม่มีเอกสาร' : ' · No documents'),
      ));
    }
    return Text.rich(
      TextSpan(
        style: const TextStyle(fontSize: 12.5, color: PgTokens.colorTextMuted),
        children: parts,
      ),
    );
  }
}

/// The "ดูรีวิว / View reviews" link-button — a small primary-tinted text affordance with its own
/// tap target so it opens the reviews sheet WITHOUT triggering the card's radio-select.
class _ViewReviewsButton extends ConsumerWidget {
  const _ViewReviewsButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(PgTokens.radiusMd),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isThai ? 'ดูรีวิว' : 'View reviews',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: PgTokens.colorPrimary,
              ),
            ),
            const SizedBox(width: 2),
            const Icon(Icons.chevron_right,
                size: 15, color: PgTokens.colorPrimary),
          ],
        ),
      ),
    );
  }
}
