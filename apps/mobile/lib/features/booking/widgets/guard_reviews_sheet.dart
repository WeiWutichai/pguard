import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../../core/controllers/guard_ratings_controller.dart';
import '../../../core/controllers/locale_controller.dart';
import '../../../core/models/rating.dart';
import '../../../core/network/api_exception.dart';
import '../../../widgets/star_rating.dart';

/// Open the customer-facing "ดูรีวิว / View reviews" sheet for one guard. Fetches
/// `GET /v1/guards/{guardId}/ratings` ONCE via the [guardRatingsProvider] family (autoDispose —
/// the request is torn down when the sheet closes) and shows the aggregate (avg stars + count)
/// then the visible reviews newest-first. Read-only; it never selects the guard, so opening it
/// from a card does NOT disturb the first-come radio selection.
Future<void> showGuardReviewsSheet({
  required BuildContext context,
  required String guardId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: PgTokens.colorSurface,
    shape: const RoundedRectangleBorder(
      borderRadius:
          BorderRadius.vertical(top: Radius.circular(PgTokens.radius2xl)),
    ),
    builder: (_) => _GuardReviewsSheet(guardId: guardId),
  );
}

class _GuardReviewsSheet extends ConsumerWidget {
  const _GuardReviewsSheet({required this.guardId});

  final String guardId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;

    return DraggableScrollableSheet(
      // A peek-then-expand sheet: opens at ~70% height, can be dragged to near-full or down to
      // dismiss — the same scrollable-sheet convention the check-in sheet uses.
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Column(
        children: [
          // Grab handle.
          const SizedBox(height: PgTokens.space2),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: PgTokens.colorBorderStrong,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(PgTokens.space4, PgTokens.space3,
                PgTokens.space4, PgTokens.space2),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    isThai ? 'รีวิวเจ้าหน้าที่' : 'Guard reviews',
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.close, color: PgTokens.colorTextMuted),
                  tooltip: isThai ? 'ปิด' : 'Close',
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: PgTokens.colorBorder),
          Expanded(
            child: ref.watch(guardRatingsProvider(guardId)).when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => _ErrorState(
                    isThai: isThai,
                    message: e is ApiException ? e.message : null,
                    onRetry: () =>
                        ref.invalidate(guardRatingsProvider(guardId)),
                  ),
                  data: (r) => r.hasRatings
                      ? _Content(
                          ratings: r,
                          isThai: isThai,
                          scrollController: scrollController,
                        )
                      : _EmptyState(
                          isThai: isThai,
                          scrollController: scrollController),
                ),
          ),
        ],
      ),
    );
  }
}

/// Aggregate header (avg stars + count) + the visible reviews, newest-first.
class _Content extends StatelessWidget {
  const _Content({
    required this.ratings,
    required this.isThai,
    required this.scrollController,
  });

  final GuardRatings ratings;
  final bool isThai;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    // `_Content` is only built when `hasRatings` (so `averageValue` is non-null) — the empty
    // state handles the no-reviews case instead of faking a 0.0.
    final avg = ratings.averageValue!;
    // Newest-first: the contract returns reviews in an unspecified order, so sort defensively by
    // `created_at` descending for display (does not mutate the source list).
    final reviews = [...ratings.reviews]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(
          PgTokens.space4, PgTokens.space4, PgTokens.space4, PgTokens.space6),
      children: [
        // Aggregate: big numeric average + whole-star display + the visible-review count.
        Row(
          children: [
            Text(
              avg.toStringAsFixed(1),
              style: const TextStyle(
                fontFamily: 'IBMPlexMono',
                fontSize: 38,
                fontWeight: FontWeight.w600,
                color: PgTokens.colorTextStrong,
              ),
            ),
            const SizedBox(width: PgTokens.space3),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StarRatingDisplay(value: avg.round(), size: 16),
                const SizedBox(height: 4),
                Text(
                  isThai
                      ? 'จาก ${ratings.count} รีวิว'
                      : 'from ${ratings.count} reviews',
                  style: const TextStyle(
                      fontSize: 12.5, color: PgTokens.colorTextMuted),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: PgTokens.space3),
        const Divider(height: 1, color: PgTokens.colorBorder),
        for (final review in reviews) _ReviewItem(review: review),
      ],
    );
  }
}

/// One visible review: reviewer initial (when present) + date + stars, then the comment. The
/// public discovery contract exposes NO reviewer identity (PDPA), so [Review] carries no name —
/// a generic person avatar stands in rather than a faked initial.
class _ReviewItem extends StatelessWidget {
  const _ReviewItem({required this.review});

  final Review review;

  static String _fmtDate(DateTime d) {
    final l = d.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(l.day)}/${two(l.month)}/${l.year}';
  }

  @override
  Widget build(BuildContext context) {
    // The contract has no reviewer name; show the first letter only if one is ever present,
    // otherwise the generic person icon (honest, not faked).
    final initial = review.reviewerInitial;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 13),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: PgTokens.colorBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 15,
                backgroundColor: PgTokens.colorGreen100,
                child: initial == null
                    ? const Icon(Icons.person_outline,
                        size: 16, color: PgTokens.colorGreen800)
                    : Text(
                        initial,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: PgTokens.colorGreen800,
                        ),
                      ),
              ),
              const SizedBox(width: PgTokens.space2),
              Text(
                _fmtDate(review.createdAt),
                style: const TextStyle(
                    fontSize: 12, color: PgTokens.colorTextMuted),
              ),
              const Spacer(),
              StarRatingDisplay(value: review.overallRating, size: 13),
            ],
          ),
          if (review.reviewText case final text? when text.trim().isNotEmpty) ...[
            const SizedBox(height: 7),
            Text(
              text,
              style: const TextStyle(
                  fontSize: 13, height: 1.5, color: PgTokens.colorTextMuted),
            ),
          ],
        ],
      ),
    );
  }
}

/// Friendly empty state — a guard with no visible reviews yet. Scrollable so the sheet can still
/// be dragged/dismissed.
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.isThai, required this.scrollController});

  final bool isThai;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: scrollController,
      children: [
        Padding(
          padding: const EdgeInsets.all(PgTokens.space6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: PgTokens.space6),
              const Icon(Icons.star_outline_rounded,
                  size: 48, color: PgTokens.colorTextFaint),
              const SizedBox(height: PgTokens.space3),
              Text(
                isThai ? 'ยังไม่มีรีวิว' : 'No reviews yet',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: PgTokens.space2),
              Text(
                isThai
                    ? 'เจ้าหน้าที่คนนี้ยังไม่มีรีวิวจากลูกค้า'
                    : 'This guard has no customer reviews yet',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 13, color: PgTokens.colorTextMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Error state with a retry — kept inside the sheet (a compact variant of [PgErrorState] so it
/// fits the sheet rather than a full screen).
class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.isThai,
    required this.onRetry,
    this.message,
  });

  final bool isThai;
  final VoidCallback onRetry;
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(PgTokens.space6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined,
                size: 44, color: PgTokens.colorDanger),
            const SizedBox(height: PgTokens.space3),
            Text(
              isThai ? 'โหลดรีวิวไม่สำเร็จ' : 'Could not load reviews',
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            if (message != null) ...[
              const SizedBox(height: PgTokens.space2),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 13, height: 1.5, color: PgTokens.colorTextMuted),
              ),
            ],
            const SizedBox(height: PgTokens.space4),
            OutlinedButton(
              onPressed: onRetry,
              child: Text(isThai ? 'ลองอีกครั้ง' : 'Try again'),
            ),
          ],
        ),
      ),
    );
  }
}
