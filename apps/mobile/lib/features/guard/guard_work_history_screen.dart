import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../core/controllers/customer_home_controller.dart' show thaiShortDate;
import '../../core/controllers/earnings.dart';
import '../../core/controllers/guard_jobs_controller.dart';
import '../../core/controllers/locale_controller.dart';
import '../../core/models/booking.dart';
import '../../core/models/money.dart';
import '../../core/network/api_exception.dart';
import '../../widgets/pg_error_state.dart';
import '../../widgets/pg_segmented_tabs.dart';
import '../../widgets/pguard_header.dart';

/// The guard's "ประวัติงาน / Work history" screen (design `Mobile - Guard App.html` ⑦): a
/// Completed / Cancelled segmented control over the guard's past bookings (`GET /v1/bookings`,
/// the same one-shot feed the dashboard/jobs/earnings screens share — no polling;
/// pull-to-refresh re-pulls). Rows follow `.prow`; tapping opens the read-only job detail.
class GuardWorkHistoryScreen extends ConsumerStatefulWidget {
  const GuardWorkHistoryScreen({super.key});

  @override
  ConsumerState<GuardWorkHistoryScreen> createState() =>
      _GuardWorkHistoryScreenState();
}

class _GuardWorkHistoryScreenState
    extends ConsumerState<GuardWorkHistoryScreen> {
  int _tab = 0; // Completed.

  /// Newest first (by scheduled time); unscheduled rows sink to the bottom.
  static List<Booking> _byRecent(Iterable<Booking> xs) {
    final list = xs.toList();
    list.sort((a, b) {
      final da = a.scheduledAt, db = b.scheduledAt;
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return db.compareTo(da);
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    final async = ref.watch(guardJobsControllerProvider);
    final ctrl = ref.read(guardJobsControllerProvider.notifier);

    return Scaffold(
      backgroundColor: PgTokens.colorBg,
      appBar: PGuardHeader(light: true, 
        title: isThai ? 'ประวัติงาน' : 'Work history',
        showBack: true,
      ),
      body: SafeArea(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => PgErrorState(
            title: isThai ? 'โหลดประวัติไม่สำเร็จ' : 'Could not load history',
            message: e is ApiException ? e.message : null,
            onRetry: ctrl.refresh,
          ),
          data: (all) {
            final completed =
                _byRecent(GuardJobsController.completed(all));
            // A guard's "cancelled" archive: jobs the customer cancelled and jobs the guard
            // declined/withdrew from — both ended without completion.
            final cancelled = _byRecent(all.where((b) =>
                b.status == BookingStatus.cancelled ||
                b.status == BookingStatus.declined));
            final groups = [completed, cancelled];
            final current = groups[_tab];

            return Column(
              children: [
                PgSegmentedTabs(
                  labels: isThai
                      ? const ['เสร็จสิ้น', 'ยกเลิก']
                      : const ['Completed', 'Cancelled'],
                  counts: [completed.length, cancelled.length],
                  selected: _tab,
                  onSelect: (i) => setState(() => _tab = i),
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: ctrl.refresh,
                    child: current.isEmpty
                        ? _Empty(isThai: isThai, completedTab: _tab == 0)
                        : ListView.builder(
                            padding: const EdgeInsets.only(bottom: 12),
                            itemCount: current.length,
                            itemBuilder: (_, i) => _HistoryRow(
                              booking: current[i],
                              isThai: isThai,
                              completed: _tab == 0,
                            ),
                          ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Design `.prow`: a 38×38 sunken icon tile + place / date, then the earned amount (completed) or
/// a "ยกเลิก / Cancelled" tag, and a chevron. Tapping opens the read-only job detail.
class _HistoryRow extends StatelessWidget {
  const _HistoryRow(
      {required this.booking, required this.isThai, required this.completed});

  final Booking booking;
  final bool isThai;
  final bool completed;

  @override
  Widget build(BuildContext context) {
    final when = booking.scheduledAt;
    final meta = [
      if (when != null) thaiShortDate(when, isThai: isThai),
      '${booking.hours ?? 0} ${isThai ? 'ชม.' : 'hrs'}',
    ].join(' · ');

    return InkWell(
      onTap: () => context.push('/guard/job/${booking.id}'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: PgTokens.colorBorder)),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: PgTokens.colorSunken,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(
                  completed
                      ? Icons.shield_outlined
                      : Icons.cancel_outlined,
                  size: 18,
                  color: PgTokens.colorTextMuted),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    booking.address ??
                        (isThai ? 'งานรักษาความปลอดภัย' : 'Security job'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: PgTokens.colorTextStrong),
                  ),
                  const SizedBox(height: 1),
                  Text(meta,
                      style: const TextStyle(
                          fontSize: 11.5, color: PgTokens.colorTextMuted)),
                ],
              ),
            ),
            const SizedBox(width: PgTokens.space2),
            if (completed)
              Text(
                Money.format(GuardEarnings.jobEarningsSatang(booking)),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'IBMPlexMono',
                  fontFeatures: [FontFeature.tabularFigures()],
                  color: PgTokens.colorTextStrong,
                ),
              )
            else
              Text(isThai ? 'ยกเลิก' : 'Cancelled',
                  style: const TextStyle(
                      fontSize: 12.5, color: PgTokens.colorTextMuted)),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right,
                size: 20, color: PgTokens.colorTextFaint),
          ],
        ),
      ),
    );
  }
}

/// Per-tab empty state (scrollable so pull-to-refresh still works).
class _Empty extends StatelessWidget {
  const _Empty({required this.isThai, required this.completedTab});

  final bool isThai;
  final bool completedTab;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 96),
        Icon(
            completedTab
                ? Icons.check_circle_outline
                : Icons.cancel_outlined,
            size: 48,
            color: PgTokens.colorTextFaint),
        const SizedBox(height: PgTokens.space3),
        Text(
          completedTab
              ? (isThai ? 'ยังไม่มีงานที่เสร็จ' : 'No completed jobs yet')
              : (isThai ? 'ยังไม่มีงานที่ยกเลิก' : 'No cancelled jobs'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: PgTokens.space2),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: PgTokens.space6),
          child: Text(
            completedTab
                ? (isThai
                    ? 'งานที่ทำเสร็จแล้วจะแสดงที่นี่'
                    : 'Your completed jobs appear here')
                : (isThai
                    ? 'งานที่ถูกยกเลิกจะแสดงที่นี่'
                    : 'Cancelled jobs appear here'),
            textAlign: TextAlign.center,
            style:
                const TextStyle(fontSize: 13, color: PgTokens.colorTextMuted),
          ),
        ),
      ],
    );
  }
}
