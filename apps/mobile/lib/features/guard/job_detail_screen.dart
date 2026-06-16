import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_design_tokens/pguard_design_tokens.dart';

import '../../core/controllers/active_job_controller.dart';
import '../../core/controllers/guard_jobs_controller.dart';
import '../../core/controllers/locale_controller.dart';
import '../../core/models/booking.dart';
import '../../core/models/money.dart';
import '../../core/network/api_exception.dart';
import '../../widgets/pg_error_state.dart';
import '../../widgets/primary_button.dart';
import '../booking/widgets/map_canvas.dart';

/// Incoming-job detail (design `Mobile - Guard App.html` ③): a 160px map preview with a floating
/// glass back button, then a rounded-top sheet — place title + service/hours, a customer row and a
/// time row (with the fee) in 40×40 icon tiles — and an accept/decline footer. accept (POST) →
/// the active-job screen; decline (first-come local dismiss) → back to the dashboard.
class JobDetailScreen extends ConsumerWidget {
  const JobDetailScreen({super.key, required this.bookingId});

  final String bookingId;

  Future<void> _accept(BuildContext context, WidgetRef ref) async {
    final err =
        await ref.read(guardJobsControllerProvider.notifier).accept(bookingId);
    if (!context.mounted) return;
    if (err != null) {
      _snack(context, err);
    } else {
      context.go('/guard/active/$bookingId');
    }
  }

  // First-come-accept: declining an unaccepted offer is a local dismiss, not a server call.
  void _dismiss(BuildContext context, WidgetRef ref) {
    ref.read(guardJobsControllerProvider.notifier).dismiss(bookingId);
    context.pop();
  }

  static void _snack(BuildContext context, String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isThai = ref.watch(localeControllerProvider) == AppLocale.th;
    final async = ref.watch(activeJobControllerProvider(bookingId));

    return Scaffold(
      backgroundColor: PgTokens.colorBg,
      body: async.when(
        loading: () => const _Plain(
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => _Plain(
          child: PgErrorState(
            title: isThai ? 'โหลดงานไม่สำเร็จ' : 'Could not load this job',
            message: e is ApiException ? e.message : null,
            onRetry: () =>
                ref.invalidate(activeJobControllerProvider(bookingId)),
          ),
        ),
        data: (state) => _Body(
          isThai: isThai,
          booking: state.booking,
          onAccept: () => _accept(context, ref),
          onDismiss: () => _dismiss(context, ref),
        ),
      ),
    );
  }
}

/// Loading/error chrome: a centered child with a plain back affordance (the glass-on-map button
/// only makes sense once the map is showing).
class _Plain extends StatelessWidget {
  const _Plain({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Stack(
        children: [
          Positioned.fill(child: child),
          Positioned(
            top: PgTokens.space2,
            left: PgTokens.space3,
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: PgTokens.colorTextStrong),
              onPressed: () => context.pop(),
            ),
          ),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.isThai,
    required this.booking,
    required this.onAccept,
    required this.onDismiss,
  });

  final bool isThai;
  final Booking booking;
  final VoidCallback onAccept;
  final VoidCallback onDismiss;

  /// Booking fee = base_fee × hours × guard_count (server-owned base_fee, in satang).
  int get _feeSatang => Money.total(
        baseFeeSatang: Money.satangFromString(booking.baseFee),
        hours: booking.hours ?? 0,
        guardCount: booking.guardCount ?? 1,
      );

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    const mapHeight = 160.0;
    const sheetOverlap = 8.0; // design `.sheet { margin-top:-8px }`
    final mapBand = mapHeight + topInset; // the map bleeds under the status bar
    final canAccept = booking.status == BookingStatus.requested;

    return Stack(
      children: [
        // 1) The painted map preview, bleeding to the very top.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: mapBand,
          child: const _MapPreview(),
        ),
        // 2) The sheet, overlapping the map's bottom by 8px and filling the rest.
        Column(
          children: [
            SizedBox(height: mapBand - sheetOverlap),
            Expanded(
              child: _Sheet(
                isThai: isThai,
                booking: booking,
                feeSatang: _feeSatang,
                canAccept: canAccept,
                onAccept: onAccept,
                onDismiss: onDismiss,
              ),
            ),
          ],
        ),
        // 3) Floating glass back button over the map.
        Positioned(
          top: topInset + PgTokens.space2,
          left: PgTokens.space3,
          child: _GlassBack(onTap: () => context.pop()),
        ),
      ],
    );
  }
}

/// Design `.map`: a stylised painted backdrop (no tiles/SDK) with a centred job-location pin.
class _MapPreview extends StatelessWidget {
  const _MapPreview();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(child: CustomPaint(painter: MapBackdropPainter())),
        Center(
          child: Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 8,
                    offset: const Offset(0, 2)),
              ],
            ),
            child: const Icon(Icons.location_on,
                color: PgTokens.colorPrimary, size: 24),
          ),
        ),
      ],
    );
  }
}

/// Design `.iconbtn.glass`: a translucent white circle with the brand-green chevron.
class _GlassBack extends StatelessWidget {
  const _GlassBack({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.92),
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: const Padding(
          padding: EdgeInsets.all(10),
          child: Icon(Icons.arrow_back_ios_new,
              size: 18, color: PgTokens.colorBrand),
        ),
      ),
    );
  }
}

/// Design `.sheet`: a rounded-top surface (grab handle) holding the detail rows + the footer.
class _Sheet extends StatelessWidget {
  const _Sheet({
    required this.isThai,
    required this.booking,
    required this.feeSatang,
    required this.canAccept,
    required this.onAccept,
    required this.onDismiss,
  });

  final bool isThai;
  final Booking booking;
  final int feeSatang;
  final bool canAccept;
  final VoidCallback onAccept;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final hours = booking.hours;
    final customerRef = booking.customerId.length >= 8
        ? '#${booking.customerId.substring(0, 8)}'
        : '#${booking.customerId}';
    final guardCount = booking.guardCount ?? 1;

    final rows = <Widget>[
      // Customer — the contract carries no customer name pre-accept, so the short reference id
      // stands in (honest, matching the app's #id convention); the name needs a profile read.
      _DetailRow(
        icon: Icons.person_outline,
        label: isThai ? 'ลูกค้า' : 'Customer',
        value: customerRef,
      ),
      _DetailRow(
        icon: Icons.calendar_today_outlined,
        label: isThai ? 'เวลา' : 'Time',
        value:
            JobDetailTime.window(booking.scheduledAt, hours, DateTime.now(),
                isThai: isThai),
        trailing: Text(
          Money.format(feeSatang),
          style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              fontFamily: 'IBMPlexMono',
              fontFeatures: [FontFeature.tabularFigures()]),
        ),
      ),
      // A guards row only for multi-guard jobs (the common single-guard case mirrors the mockup's
      // two-row sheet exactly).
      if (guardCount > 1)
        _DetailRow(
          icon: Icons.people_outline,
          label: isThai ? 'จำนวนเจ้าหน้าที่' : 'Guards',
          value: isThai ? '$guardCount คน' : '$guardCount guards',
        ),
    ];

    return Container(
      decoration: const BoxDecoration(
        color: PgTokens.colorSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        boxShadow: [
          BoxShadow(
              color: Color(0x29082619), blurRadius: 36, offset: Offset(0, -10)),
        ],
      ),
      child: Column(
        children: [
          // Grab handle.
          Container(
            width: 42,
            height: 5,
            margin: const EdgeInsets.only(top: 6, bottom: 14),
            decoration: BoxDecoration(
              color: PgTokens.colorBorderStrong,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              // When there's no footer (already-accepted etc.) the scroll tail must still clear
              // the gesture-nav home indicator; the footer handles its own inset below.
              padding: EdgeInsets.only(
                  bottom: canAccept
                      ? 0
                      : MediaQuery.of(context).padding.bottom + 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          booking.address ??
                              (isThai ? 'งานรักษาความปลอดภัย' : 'Security job'),
                          style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w600,
                              color: PgTokens.colorTextStrong),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isThai
                              ? (hours != null
                                  ? 'รปภ. ประจำจุด · $hours ชั่วโมง'
                                  : 'รปภ. ประจำจุด')
                              : (hours != null
                                  ? 'On-site guard · $hours hrs'
                                  : 'On-site guard'),
                          style: const TextStyle(
                              fontSize: 12.5, color: PgTokens.colorTextMuted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  for (var i = 0; i < rows.length; i++)
                    DecoratedBox(
                      decoration: i == 0
                          ? const BoxDecoration()
                          : const BoxDecoration(
                              border: Border(
                                  top: BorderSide(color: PgTokens.colorBorder))),
                      child: rows[i],
                    ),
                  if (!canAccept)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                      child: Text(
                        isThai
                            ? 'สถานะ: ${BookingLifecycle.labelTh(booking.status)}'
                            : 'Status: ${BookingLifecycle.labelEn(booking.status)}',
                        style: const TextStyle(color: PgTokens.colorTextMuted),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (canAccept)
            // Design ③ footer: no top border, decline (ghost pill) + accept (green), gap 9.
            Padding(
              padding: EdgeInsets.fromLTRB(
                  20, 8, 20, 16 + MediaQuery.of(context).padding.bottom),
              child: Row(
                children: [
                  // ~90px in the mockup; widened so the Thai "ปฏิเสธ" label clears Flutter's
                  // default button padding without wrapping.
                  SizedBox(
                    width: 116,
                    child: PgPrimaryButton(
                      label: isThai ? 'ปฏิเสธ' : 'Decline',
                      color: PgTokens.colorSunken,
                      foreground: PgTokens.colorTextStrong,
                      onPressed: onDismiss,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: PgPrimaryButton(
                        label: isThai ? 'รับงานนี้' : 'Accept job',
                        onPressed: onAccept),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Design `.row`: a 40×40 green icon tile + label/value, with an optional right-aligned trailing
/// (the เวลา row puts the mono fee there). Consecutive rows are separated by a top hairline.
class _DetailRow extends StatelessWidget {
  const _DetailRow(
      {required this.icon,
      required this.label,
      required this.value,
      this.trailing});

  final IconData icon;
  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: PgTokens.colorGreen50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 18, color: PgTokens.colorGreen700),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 11.5, color: PgTokens.colorTextMuted)),
                const SizedBox(height: 1),
                Text(value,
                    style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: PgTokens.colorTextStrong)),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: PgTokens.space2),
            trailing!,
          ],
        ],
      ),
    );
  }
}

/// Pure formatter for the เวลา row value ("วันนี้ 14:00 – 22:00"). Static + widget-free so it
/// is unit-testable. (The design's fix sketch shares GuardJobCard._timeWindow, but
/// `widgets/job_card.dart` is outside this slice's ownership — re-implemented here.)
class JobDetailTime {
  const JobDetailTime._();

  static String _two(int n) => n.toString().padLeft(2, '0');

  /// "วันนี้ HH:MM – HH:MM" / "Today …" when [scheduledAt] falls on [now]'s local date, else
  /// "D/M HH:MM – HH:MM"; falls back to the bare hours ("8 ชม." / "8 hrs") or "—" when unscheduled.
  static String window(DateTime? scheduledAt, int? hours, DateTime now,
      {required bool isThai}) {
    final start = scheduledAt?.toLocal();
    if (start == null) {
      return hours != null ? '$hours ${isThai ? 'ชม.' : 'hrs'}' : '—';
    }
    final end = start.add(Duration(hours: hours ?? 0));
    final sameDay = start.year == now.year &&
        start.month == now.month &&
        start.day == now.day;
    final today = isThai ? 'วันนี้' : 'Today';
    final day = sameDay ? today : '${start.day}/${start.month}';
    return '$day ${_two(start.hour)}:${_two(start.minute)} – '
        '${_two(end.hour)}:${_two(end.minute)}';
  }
}
