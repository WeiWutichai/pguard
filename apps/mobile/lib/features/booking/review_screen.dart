import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../core/controllers/locale_controller.dart';
import '../../core/controllers/review_controller.dart';
import '../../widgets/pguard_header.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/star_rating.dart';

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
    final outcome =
        await ref.read(reviewControllerProvider.notifier).submit(
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
      case ReviewOutcome.submitted:
        _toast(isThai ? 'ขอบคุณสำหรับรีวิว' : 'Thanks for your review');
        context.pop();
      case ReviewOutcome.alreadyReviewed:
        _toast(isThai ? 'คุณรีวิวงานนี้แล้ว' : 'You already reviewed this job');
        context.pop();
      case ReviewOutcome.error:
        break; // state.error renders inline below
    }
  }

  void _toast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    final state = ref.watch(reviewControllerProvider);

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
                      isThai
                          ? 'เจ้าหน้าที่รักษาความปลอดภัย'
                          : 'Security guard',
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isThai ? 'บริการเป็นอย่างไรบ้าง?' : 'How was the service?',
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
                        borderRadius:
                            BorderRadius.circular(PgTokens.radiusXl),
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
