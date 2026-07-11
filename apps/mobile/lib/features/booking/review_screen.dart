import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../core/controllers/booking_payment_controller.dart';
import '../../core/controllers/booking_status_controller.dart';
import '../../core/controllers/customer_home_controller.dart';
import '../../core/controllers/locale_controller.dart';
import '../../core/controllers/my_review_controller.dart';
import '../../core/controllers/review_controller.dart';
import '../../widgets/pguard_header.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/star_rating.dart';
import 'widgets/job_receipt_sheet.dart';

/// Customer review screen for a completed booking (design `Mobile - Customer App.html` ⑫ "รีวิว"):
/// a required overall ★ + optional per-category ministars (ตรงเวลา / มืออาชีพ / สื่อสาร / การแต่งกาย)
/// + an optional comment → `POST /v1/assignments/{id}/review`. The reviewed guard + the
/// customer/completed checks are enforced server-side. One review per assignment → a duplicate
/// (409) is handled gracefully. `assignmentId` is the booking id.
class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key, required this.bookingId});

  final String bookingId;

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  int _overall = 0;
  int _punctuality = 0;
  int _professionalism = 0;
  int _communication = 0;
  int _appearance = 0;
  final _comment = TextEditingController();

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final isThai = ref.read(localeControllerProvider) == AppLocale.th;
    int? opt(int v) => v > 0 ? v : null;
    final outcome = await ref.read(reviewControllerProvider.notifier).submit(
          assignmentId: widget.bookingId,
          overallRating: _overall,
          punctuality: opt(_punctuality),
          professionalism: opt(_professionalism),
          communication: opt(_communication),
          appearance: opt(_appearance),
          reviewText: _comment.text,
        );
    if (!mounted) return;
    switch (outcome) {
      // A fresh submit AND an already-reviewed booking both END the review flow successfully:
      // thank the customer, then leave the rating screen. Idempotent — a 409 ("คุณรีวิวงานนี้แล้ว")
      // is a normal end state, not an error, so it gets the same thank-you + escape, not a dead-end.
      case ReviewOutcome.submitted:
        // The booking is now rated: refresh the "already rated" gate (so re-opening the completed
        // booking shows the "Rated" state, not the form) before leaving.
        ref.invalidate(myReviewProvider(widget.bookingId));
        await _thankYouThenHome(isThai, alreadyReviewed: false);
      case ReviewOutcome.alreadyReviewed:
        ref.invalidate(myReviewProvider(widget.bookingId));
        await _thankYouThenHome(isThai, alreadyReviewed: true);
      case ReviewOutcome.error:
        break; // state.error renders inline below
    }
  }

  /// Show the "ขอบคุณสำหรับการรีวิว / Thank you for your review!" confirmation, then RESET the
  /// navigation stack to the customer home. We use `context.go` (not `pop`) on purpose: the review
  /// screen is reached via `pushReplacement` from the job-completion summary, so popping would land
  /// the customer back on a stale live-status / nowhere — the "รีวิวแล้วกลับหน้าหลักไม่ได้" dead-end.
  /// `go('/home/customer')` rebuilds the stack at home, always escaping it. The dialog also offers
  /// "ดูใบเสร็จ / View receipt" so the customer can see the settled bill straight from here.
  Future<void> _thankYouThenHome(bool isThai,
      {required bool alreadyReviewed}) async {
    final wantsReceipt = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.check_circle,
            size: 44, color: PgTokens.colorSuccess),
        title: Text(
          isThai ? 'ขอบคุณสำหรับการรีวิว' : 'Thank you for your review!',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        content: Text(
          alreadyReviewed
              ? (isThai
                  ? 'คุณรีวิวงานนี้แล้ว ความคิดเห็นของคุณช่วยพัฒนาบริการของเรา'
                  : "You've already reviewed this job. Your feedback helps us improve.")
              : (isThai
                  ? 'ความคิดเห็นของคุณช่วยพัฒนาบริการของเรา'
                  : 'Your feedback helps us improve our service.'),
          textAlign: TextAlign.center,
          style:
              const TextStyle(fontSize: 13.5, color: PgTokens.colorTextMuted),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.receipt_long_outlined, size: 18),
            label: Text(isThai ? 'ดูใบเสร็จ' : 'View receipt'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            style:
                FilledButton.styleFrom(backgroundColor: PgTokens.colorGreen800),
            child: Text(isThai ? 'กลับหน้าหลัก' : 'Back to home'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    // Show the receipt FIRST (and wait for it to close) when asked — otherwise navigating home
    // would tear the review screen down and dismiss the sheet immediately.
    if (wantsReceipt == true) {
      await _openReceipt(isThai);
      if (!mounted) return;
    }
    // The booking is now completed + rated, so the home's one-shot `GET /bookings` snapshot (the
    // ongoing-job card) is stale. Invalidate it so home re-pulls on landing — home does not observe
    // the booking-status WS, so without this the completed job lingers until pull-to-refresh.
    ref.invalidate(customerHomeControllerProvider);
    // Then always land the customer at home — a clean stack reset out of the review/summary/live
    // chain (escapes the "รีวิวแล้วกลับหน้าหลักไม่ได้" dead-end).
    context.go('/home/customer');
  }

  /// Open the shared job RECEIPT for this booking, enriched with the CUSTOMER's settled payment
  /// when available. The customer is the payment owner, so `GET /v1/payments` (owner-scoped, picked
  /// by booking_id via [bookingPaymentControllerProvider]) yields the authoritative reconciled
  /// `final_amount` / `refund_amount` / `actual_hours`. If the settle hasn't propagated (no row),
  /// the sheet falls back to the booking-derived estimate — it never blocks. Reuses #99's
  /// [showJobReceiptSheet].
  ///
  /// The booking snapshot is AWAITED (not `.valueOrNull`): the build-time watch usually has it
  /// resolved already, but when it hasn't (or the fetch failed) the old null-check silently
  /// no-opped the dialog's "ดูใบเสร็จ" tap — now a still-loading snapshot is waited for and a
  /// failure gets an honest snackbar instead of nothing.
  Future<void> _openReceipt(bool isThai) async {
    try {
      final booking = await ref
          .read(bookingStatusControllerProvider(widget.bookingId).future);
      if (!mounted) return;
      final payment = ref
          .read(bookingPaymentControllerProvider(widget.bookingId))
          .valueOrNull;
      await showJobReceiptSheet(
        context,
        booking: booking,
        payment: payment,
        isThai: isThai,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(isThai
            ? 'โหลดใบเสร็จไม่สำเร็จ — ลองใหม่'
            : 'Could not load the receipt — try again'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    final state = ref.watch(reviewControllerProvider);

    // Prime the booking snapshot + the customer's owner-scoped payment so they're already loaded
    // when the post-submit thank-you dialog offers "ดูใบเสร็จ / View receipt" — watching keeps both
    // alive for this screen and starts their fetch on mount (no extra request at receipt time).
    // These MUST stay above the already-rated gate below: a successful submit invalidates
    // myReviewProvider, which then resolves to the just-created review and would flip build to the
    // _AlreadyReviewed early-return — disposing these autoDispose providers WHILE the thank-you
    // dialog is still open, so a later "View receipt" tap reads a null booking and no-ops. Watching
    // here keeps them alive across that rebuild.
    ref.watch(bookingStatusControllerProvider(widget.bookingId));
    ref.watch(bookingPaymentControllerProvider(widget.bookingId));

    // Entry gate: if the customer ALREADY reviewed this booking (e.g. a deep-link / back into a
    // completed booking), show a read-only "rated" state instead of the form — a duplicate submit
    // would only 409. `null` = not rated yet (or still loading / a 404), so the form shows; the
    // forced summary→review flow always lands here BEFORE rating, so it sees the form as expected.
    final existingReview =
        ref.watch(myReviewProvider(widget.bookingId)).valueOrNull;
    if (existingReview != null) {
      return _AlreadyReviewed(rating: existingReview.overallRating);
    }

    final categories = <({String label, int value, ValueChanged<int> set})>[
      (
        label: isThai ? 'ตรงเวลา' : 'Punctuality',
        value: _punctuality,
        set: (v) => setState(() => _punctuality = v),
      ),
      (
        label: isThai ? 'มืออาชีพ' : 'Professionalism',
        value: _professionalism,
        set: (v) => setState(() => _professionalism = v),
      ),
      (
        label: isThai ? 'สื่อสาร' : 'Communication',
        value: _communication,
        set: (v) => setState(() => _communication = v),
      ),
      (
        label: isThai ? 'การแต่งกาย' : 'Appearance',
        value: _appearance,
        set: (v) => setState(() => _appearance = v),
      ),
    ];

    return Scaffold(
      appBar: PGuardHeader(
        title: isThai ? 'ให้คะแนน' : 'Rate',
        showBack: true,
        // FROZEN-BACK GUARD (same class as live/active): this is a deep-linkable top-level route
        // (`/booking/:id/review`) also reached via a pushReplacement chain (live → summary → review),
        // so it can be the navigator ROOT with nothing for the default `maybePop` to pop. Fall back to
        // the customer home so back is never a no-op. Submit already lands on home the same way.
        onBack: () =>
            context.canPop() ? context.pop() : context.go('/home/customer'),
        background: PgTokens.colorGreen800,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(PgTokens.space5),
                child: Column(
                  children: [
                    const CircleAvatar(
                      radius: 36,
                      backgroundColor: PgTokens.colorGreen100,
                      child: Icon(Icons.shield_outlined,
                          size: 32, color: PgTokens.colorGreen800),
                    ),
                    const SizedBox(height: PgTokens.space3),
                    Text(
                      isThai ? 'เจ้าหน้าที่รักษาความปลอดภัย' : 'Security guard',
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isThai
                          ? 'บริการเป็นอย่างไรบ้าง?'
                          : 'How was the service?',
                      style: const TextStyle(
                          fontSize: 13, color: PgTokens.colorTextMuted),
                    ),
                    const SizedBox(height: PgTokens.space5),
                    // Overall (required).
                    Center(
                      child: StarRatingInput(
                        value: _overall,
                        size: 38,
                        semanticPrefix: isThai ? 'คะแนนรวม' : 'Overall',
                        onChanged: (v) => setState(() => _overall = v),
                      ),
                    ),
                    const SizedBox(height: PgTokens.space5),
                    Text(
                      isThai
                          ? 'ให้คะแนนแยกหมวด (ไม่บังคับ)'
                          : 'Rate by category (optional)',
                      style: const TextStyle(
                          fontSize: 12.5, color: PgTokens.colorTextMuted),
                    ),
                    const SizedBox(height: PgTokens.space2),
                    for (final c in categories)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(c.label,
                                  style: const TextStyle(fontSize: 13.5)),
                            ),
                            StarRatingInput(
                              value: c.value,
                              size: 18,
                              semanticPrefix: c.label,
                              onChanged: c.set,
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: PgTokens.space4),
                    // Optional comment (design `.card sunken`).
                    Container(
                      decoration: BoxDecoration(
                        color: PgTokens.colorSunken,
                        borderRadius: BorderRadius.circular(PgTokens.radiusXl),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: PgTokens.space4, vertical: 4),
                      child: TextField(
                        controller: _comment,
                        minLines: 2,
                        maxLines: 5,
                        maxLength: 2000,
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          counterText: '',
                          hintText: isThai
                              ? 'เขียนรีวิว (ไม่บังคับ)'
                              : 'Write a review (optional)',
                        ),
                      ),
                    ),
                    if (state.error != null) ...[
                      const SizedBox(height: PgTokens.space3),
                      Text(state.error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: PgTokens.colorDanger)),
                    ],
                  ],
                ),
              ),
            ),
            // Footer CTA — amber per the design `.cta-amber`; enabled once the overall is set.
            Container(
              decoration: const BoxDecoration(
                color: PgTokens.colorSurface,
                border: Border(top: BorderSide(color: PgTokens.colorBorder)),
              ),
              padding: const EdgeInsets.fromLTRB(
                  20, PgTokens.space4, 20, PgTokens.space4),
              child: PgPrimaryButton(
                label: isThai ? 'ส่งรีวิว' : 'Submit review',
                // Design `.cta-amber`: dark label on amber (not the default white) for contrast.
                color: PgTokens.colorAmber500,
                foreground: PgTokens.colorOnAmber,
                busy: state.busy,
                onPressed: _overall == 0 || state.busy ? null : _submit,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Read-only "already rated" state for a booking the customer has reviewed — shown when
/// [ReviewScreen] is entered for a booking that already has the caller's review (a deep-link or a
/// re-open). Prevents a pointless re-submit that would 409; the only action is back to home.
class _AlreadyReviewed extends ConsumerWidget {
  const _AlreadyReviewed({required this.rating});

  final int rating;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    return Scaffold(
      appBar: PGuardHeader(
        title: isThai ? 'ให้คะแนน' : 'Rate',
        showBack: true,
        onBack: () =>
            context.canPop() ? context.pop() : context.go('/home/customer'),
        background: PgTokens.colorGreen800,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(PgTokens.space5),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.check_circle,
                  size: 56, color: PgTokens.colorSuccess),
              const SizedBox(height: PgTokens.space3),
              Text(
                isThai
                    ? 'คุณให้คะแนนงานนี้แล้ว'
                    : "You've already rated this job",
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: PgTokens.space3),
              StarRatingDisplay(value: rating, size: 30),
              const SizedBox(height: PgTokens.space2),
              Text(
                isThai
                    ? 'ความคิดเห็นของคุณช่วยพัฒนาบริการของเรา'
                    : 'Your feedback helps us improve our service.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 13, color: PgTokens.colorTextMuted),
              ),
              const SizedBox(height: PgTokens.space5),
              PgPrimaryButton(
                label: isThai ? 'กลับหน้าหลัก' : 'Back to home',
                color: PgTokens.colorGreen800,
                onPressed: () => context.go('/home/customer'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
