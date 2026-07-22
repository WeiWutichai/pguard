import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../network/api_error_l10n.dart';
import '../network/api_exception.dart';
import '../providers.dart';
import 'locale_controller.dart';

part 'review_controller.g.dart';

/// Outcome of a review submit.
enum ReviewOutcome {
  /// 200 — review created.
  submitted,

  /// 409 — one review per assignment; this booking was already reviewed.
  alreadyReviewed,

  /// Validation/network/other failure — `state.error` carries a user-safe message.
  error,
}

const Object _unset = Object();

class ReviewState {
  const ReviewState({this.busy = false, this.error});
  final bool busy;
  final String? error;

  ReviewState copyWith({bool? busy, Object? error = _unset}) => ReviewState(
        busy: busy ?? this.busy,
        error: identical(error, _unset) ? this.error : error as String?,
      );
}

/// Submits a customer review for a completed booking (`POST /v1/assignments/{id}/review`).
/// `overall_rating` is required (1..5); category ratings + text are optional. The reviewed
/// guard + the customer/completed checks are enforced server-side (the body never carries
/// guard_id). One review per assignment → a duplicate is a 409 ([ReviewOutcome.alreadyReviewed]).
@riverpod
class ReviewController extends _$ReviewController {
  @override
  ReviewState build() => const ReviewState();

  Future<ReviewOutcome> submit({
    required String assignmentId,
    required int overallRating,
    int? punctuality,
    int? professionalism,
    int? communication,
    int? appearance,
    String? reviewText,
  }) async {
    if (state.busy) return ReviewOutcome.error; // re-entrancy latch (no double submit)
    final isThai = ref.read(localeControllerProvider) == AppLocale.th;
    state = state.copyWith(busy: true, error: null);
    final text = reviewText?.trim();
    try {
      await ref.read(pguardApiProvider).post(
        '/assignments/$assignmentId/review',
        data: {
          'overall_rating': overallRating,
          if (punctuality != null) 'punctuality': punctuality,
          if (professionalism != null) 'professionalism': professionalism,
          if (communication != null) 'communication': communication,
          if (appearance != null) 'appearance': appearance,
          if (text != null && text.isNotEmpty) 'review_text': text,
        },
      );
      state = state.copyWith(busy: false);
      return ReviewOutcome.submitted;
    } on ApiException catch (e) {
      // 409 = already reviewed (single-use per assignment) — a normal, non-error end state.
      if (e.statusCode == 409) {
        state = state.copyWith(busy: false);
        return ReviewOutcome.alreadyReviewed;
      }
      state = state.copyWith(busy: false, error: localizeApiError(ref.read(localeControllerProvider) == AppLocale.th, e));
      return ReviewOutcome.error;
    } catch (_) {
      state = state.copyWith(
          busy: false,
          error: isThai ? 'เกิดข้อผิดพลาด' : 'Something went wrong');
      return ReviewOutcome.error;
    }
  }
}
