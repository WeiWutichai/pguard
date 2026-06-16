import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../core/controllers/guard_jobs_controller.dart';
import '../../core/controllers/locale_controller.dart';
import '../../core/models/booking.dart';
import '../../core/network/api_exception.dart';
import '../../widgets/pg_error_state.dart';
import '../../widgets/pguard_header.dart';
import 'widgets/job_card.dart';

/// The guard's "งานของฉัน / My Jobs" screen (design `Mobile - Guard App.html` ②): a 3-tab
/// segmented control over the guard's bookings — รอตอบรับ / กำลังทำ / เสร็จ (Pending / Active /
/// Done) — fed by the one-shot `GET /v1/bookings` list (no polling; pull-to-refresh re-fetches).
///
/// NOTE (v2): that feed returns only ALREADY-ASSIGNED jobs (there is no open-job discovery yet),
/// so the Pending tab is structurally empty until a discovery endpoint exists — the screen opens
/// on Active, the guard's first useful view.
class GuardJobsScreen extends ConsumerStatefulWidget {
  const GuardJobsScreen({super.key});

  @override
  ConsumerState<GuardJobsScreen> createState() => _GuardJobsScreenState();
}

class _GuardJobsScreenState extends ConsumerState<GuardJobsScreen> {
  int _tab = 1; // Active (see class note: Pending is empty in v2).

  @override
  Widget build(BuildContext context) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    final async = ref.watch(guardJobsControllerProvider);
    final ctrl = ref.read(guardJobsControllerProvider.notifier);

    return Scaffold(
      backgroundColor: PgTokens.colorBg,
      appBar: PGuardHeader(
        title: isThai ? 'งานของฉัน' : 'My Jobs',
        showBack: true,
      ),
      body: SafeArea(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => PgErrorState(
            title: isThai ? 'โหลดงานไม่สำเร็จ' : 'Could not load jobs',
            message: e is ApiException ? e.message : null,
            onRetry: ctrl.refresh,
          ),
          data: (all) {
            final groups = <List<Booking>>[
              GuardJobsController.incoming(all),
              GuardJobsController.active(all),
              GuardJobsController.completed(all),
            ];
            final current = groups[_tab];

            return Column(
              children: [
                _JobTabs(
                  isThai: isThai,
                  selected: _tab,
                  counts: [groups[0].length, groups[1].length, groups[2].length],
                  onSelect: (i) => setState(() => _tab = i),
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: ctrl.refresh,
                    child: current.isEmpty
                        ? _Empty(isThai: isThai, tab: _tab)
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                            itemCount: current.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 12),
                            itemBuilder: (_, i) {
                              final b = current[i];
                              return GuardJobCard(
                                booking: b,
                                isThai: isThai,
                                highlight: _tab == 0,
                                // Route by the booking's own status (robust to tab order):
                                // a working job → the active screen; otherwise the read-only detail.
                                onTap: () => context.push(
                                    BookingLifecycle.isActive(b.status)
                                        ? '/guard/active/${b.id}'
                                        : '/guard/job/${b.id}'),
                              );
                            },
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

/// Design `.jtabs` / `.jtab`: a 3-segment control; the active segment is a brand-green fill with
/// dark text, the rest a sunken pill with muted text.
class _JobTabs extends StatelessWidget {
  const _JobTabs({
    required this.isThai,
    required this.selected,
    required this.counts,
    required this.onSelect,
  });

  final bool isThai;
  final int selected;
  final List<int> counts;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final labels = isThai
        ? const ['รอตอบรับ', 'กำลังทำ', 'เสร็จ']
        : const ['Pending', 'Active', 'Done'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Expanded(
              child: _Seg(
                label: counts[i] > 0 ? '${labels[i]} ${counts[i]}' : labels[i],
                active: i == selected,
                onTap: () => onSelect(i),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Seg extends StatelessWidget {
  const _Seg(
      {required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? PgTokens.colorPrimary : PgTokens.colorSunken,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9),
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color:
                  active ? PgTokens.colorTextStrong : PgTokens.colorTextMuted,
            ),
          ),
        ),
      ),
    );
  }
}

/// Per-tab empty state (scrollable so pull-to-refresh still works on an empty list).
class _Empty extends StatelessWidget {
  const _Empty({required this.isThai, required this.tab});

  final bool isThai;
  final int tab;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, String title, String sub) = switch (tab) {
      0 => (
          Icons.inbox_outlined,
          isThai ? 'ยังไม่มีงานรอตอบรับ' : 'No pending jobs',
          isThai
              ? 'งานที่รอการตอบรับจะแสดงที่นี่'
              : 'Jobs awaiting your response appear here',
        ),
      1 => (
          Icons.work_outline,
          isThai ? 'ยังไม่มีงานที่กำลังทำ' : 'No active jobs',
          isThai
              ? 'งานที่รับแล้วจะแสดงที่นี่'
              : 'Jobs you have accepted appear here',
        ),
      _ => (
          Icons.check_circle_outline,
          isThai ? 'ยังไม่มีงานที่เสร็จ' : 'No completed jobs yet',
          isThai
              ? 'งานที่ทำเสร็จแล้วจะแสดงที่นี่'
              : 'Your completed jobs appear here',
        ),
    };
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 96),
        Icon(icon, size: 48, color: PgTokens.colorTextFaint),
        const SizedBox(height: PgTokens.space3),
        Text(title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: PgTokens.space2),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: PgTokens.space6),
          child: Text(sub,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 13, color: PgTokens.colorTextMuted)),
        ),
      ],
    );
  }
}
