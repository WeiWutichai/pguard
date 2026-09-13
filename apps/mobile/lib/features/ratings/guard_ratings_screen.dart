import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../core/controllers/guard_ratings_controller.dart';
import '../../core/controllers/locale_controller.dart';
import '../../core/controllers/session_controller.dart';
import '../../core/models/rating.dart';
import '../../core/network/api_exception.dart';
import '../../widgets/pg_error_state.dart';
import '../../widgets/pguard_header.dart';
import '../../widgets/star_rating.dart';

/// The guard's "รีวิวที่ได้รับ / Ratings & reviews" screen (design `Mobile - Guard App.html` ⑧):
/// the big overall average + visible-review count, the per-category bars, and the review list.
/// Reads the guard's OWN id from the session and fetches `GET /v1/guards/{id}/ratings` once (no
/// polling). Per-category averages aren't in the contract aggregate, so they're derived from the
/// returned reviews; a category with no rated reviews is simply omitted (never a fake 0.0).
///
/// THE BARS ARE NOT A BREAKDOWN OF THE HEADLINE, and the screen has to say so. They are different
/// quantities over different sets, in two independent ways:
///  · the headline is `AVG(overall_rating)` over ALL visible reviews, and each `overall_rating` was
///    already ROUNDED to a whole star by the customer's review form
///    (`features/booking/review_screen.dart` submits the category mean rounded); the bars are the
///    UNROUNDED per-category means. One 5/4/4/4 review prints a "4.0" headline over bars that
///    plainly average 4.25.
///  · the headline covers every visible review (`count`), the bars only the returned page
///    (`reviews`, max 100 — `contracts/openapi/rating.yaml`), and only those that filled the
///    optional categories in.
/// So the bars carry a caption naming their own sample, and the headline's stars are drawn from the
/// fractional average ([StarRatingAverage]) instead of `round()`ing 4.5 up to five full stars. The
/// real fix is upstream — a decimal overall in the contract, or server-side per-category averages.
class GuardRatingsScreen extends ConsumerWidget {
  const GuardRatingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    final guardId = ref.watch(sessionProvider).user?.userId;

    return Scaffold(
      appBar: PGuardHeader(
        title: isThai ? 'รีวิวที่ได้รับ' : 'Ratings & reviews',
        showBack: true,
        background: PgTokens.colorGreen800,
      ),
      body: SafeArea(
        child: guardId == null
            ? _Empty(isThai: isThai)
            : ref.watch(guardRatingsProvider(guardId)).when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => PgErrorState(
                    title: isThai
                        ? 'โหลดรีวิวไม่สำเร็จ'
                        : 'Could not load reviews',
                    message: e is ApiException ? e.message : null,
                    onRetry: () =>
                        ref.invalidate(guardRatingsProvider(guardId)),
                  ),
                  data: (r) => r.hasRatings
                      ? _Content(ratings: r, isThai: isThai)
                      : _Empty(isThai: isThai),
                ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.isThai});
  final bool isThai;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(PgTokens.space6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.star_outline_rounded,
                size: 48, color: PgTokens.colorTextFaint),
            const SizedBox(height: PgTokens.space3),
            Text(
              isThai ? 'ยังไม่มีรีวิว' : 'No reviews yet',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: PgTokens.space2),
            Text(
              isThai
                  ? 'รีวิวจากลูกค้าจะแสดงที่นี่หลังจบงาน'
                  : 'Customer reviews appear here after completed jobs',
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontSize: 13, color: PgTokens.colorTextMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({required this.ratings, required this.isThai});

  final GuardRatings ratings;
  final bool isThai;

  @override
  Widget build(BuildContext context) {
    // `_Content` is only built when `hasRatings` (so `averageValue` is non-null) — assert it
    // rather than fall back to a fake `0.0`, which the empty state (`_Empty`) handles instead.
    final avg = ratings.averageValue!;
    final categories = <({String th, String en, int? Function(Review) pick})>[
      (th: 'ตรงเวลา', en: 'Punctual', pick: (r) => r.punctuality),
      (th: 'มืออาชีพ', en: 'Pro', pick: (r) => r.professionalism),
      (th: 'สื่อสาร', en: 'Comm.', pick: (r) => r.communication),
      (th: 'การแต่งกาย', en: 'Appear.', pick: (r) => r.appearance),
    ];

    // Design ⑧ is a flat full-width scroll block (no bordered card): title, the centered
    // average, the per-category bars, then the review rows — all directly on the scroll body.
    return ListView(
      padding: const EdgeInsets.all(PgTokens.space4),
      children: [
        Text(isThai ? 'คะแนนของฉัน' : 'My rating',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: PgTokens.space3),
        Center(
          child: Column(
            children: [
              Text(
                avg.toStringAsFixed(1),
                style: const TextStyle(
                  fontFamily: 'IBMPlexMono',
                  fontSize: 46,
                  fontWeight: FontWeight.w600,
                  color: PgTokens.colorTextStrong,
                ),
              ),
              // The FRACTIONAL average, half-stars and all: `avg.round()` drew a 4.5 as five full
              // stars, a second, smaller way this screen contradicted its own printed number.
              StarRatingAverage(value: avg, size: 16),
              const SizedBox(height: 6),
              Text(
                isThai
                    ? 'จาก ${ratings.count} รีวิว'
                    : 'from ${ratings.count} reviews',
                style: const TextStyle(
                    fontSize: 12.5, color: PgTokens.colorTextMuted),
              ),
            ],
          ),
        ),
        const SizedBox(height: PgTokens.space4),
        // Name the bars and the sample they are averaged over, so they stop reading as the
        // headline's own arithmetic. Only shown when there IS a bar (a review set where nobody
        // scored a category renders none).
        if (ratings.categorySampleSize > 0) ...[
          Text(
            isThai
                ? 'เฉลี่ยรายหมวด · จาก ${ratings.categorySampleSize} รีวิวที่ให้คะแนนรายหมวด'
                : 'Per-category average · from ${ratings.categorySampleSize} reviews that scored categories',
            style:
                const TextStyle(fontSize: 11.5, color: PgTokens.colorTextMuted),
          ),
          const SizedBox(height: PgTokens.space2),
        ],
        for (final c in categories)
          if (ratings.categoryAverage(c.pick) case final v?)
            _CategoryBar(label: isThai ? c.th : c.en, value: v),
        // The aggregate above counts reviews this page did not return, so the bars are a subset of
        // what the big number averages — same caveat shape as the earnings hero's "ยอดอาจไม่ครบ".
        if (ratings.isPartialSample) ...[
          const SizedBox(height: PgTokens.space2),
          Row(
            children: [
              const Icon(Icons.info_outline,
                  size: 13, color: PgTokens.colorWarning),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  isThai
                      ? 'แสดงรีวิวล่าสุด ${ratings.reviews.length} จาก ${ratings.count} · แถบอาจไม่ครบ'
                      : 'Showing the latest ${ratings.reviews.length} of ${ratings.count} · bars may be incomplete',
                  style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: PgTokens.colorWarning),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: PgTokens.space3),
        for (final review in ratings.reviews)
          _ReviewItem(review: review, isThai: isThai),
      ],
    );
  }
}

/// Design `.catbar2`: label · track (fill = value/5) · numeric value.
class _CategoryBar extends StatelessWidget {
  const _CategoryBar({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 90, // design `.catbar2 .l { width:90px }`
            child: Text(label,
                style:
                    const TextStyle(fontSize: 12.5, color: PgTokens.colorText)),
          ),
          const SizedBox(width: 10), // design `.catbar2 { gap:10px }`
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 7,
                child: Stack(
                  children: [
                    Container(color: PgTokens.colorSunken),
                    FractionallySizedBox(
                      widthFactor: (value / 5).clamp(0.0, 1.0),
                      child: Container(color: PgTokens.colorAmber400),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 28,
            child: Text(
              value.toStringAsFixed(1),
              textAlign: TextAlign.right,
              style: const TextStyle(
                  fontFamily: 'IBMPlexMono',
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: PgTokens.colorText),
            ),
          ),
        ],
      ),
    );
  }
}

/// Design `.review-item`: stars + date, then the review text. The contract carries no reviewer
/// name, so none is shown (a generic avatar stands in) — honest, not faked.
class _ReviewItem extends StatelessWidget {
  const _ReviewItem({required this.review, required this.isThai});

  final Review review;
  final bool isThai;

  static String _fmtDate(DateTime d) {
    final l = d.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(l.day)}/${two(l.month)}/${l.year}';
  }

  @override
  Widget build(BuildContext context) {
    // Design `.review-item`: a full-width row with a bottom hairline divider (no boxed card).
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
              const CircleAvatar(
                radius: 15,
                backgroundColor: PgTokens.colorGreen100,
                child: Icon(Icons.person_outline,
                    size: 16, color: PgTokens.colorGreen800),
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
          if (review.reviewText case final text?
              when text.trim().isNotEmpty) ...[
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
