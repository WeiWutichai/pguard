import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/booking.dart';
import '../models/money.dart';
import '../network/jwt.dart';
import '../providers.dart';

part 'customer_home_controller.g.dart';

/// The customer dashboard data: the caller's bookings from `GET /v1/bookings`
/// (server-ordered NEWEST FIRST — see contracts/openapi/booking.yaml `listBookings`).
/// Fetched once per controller lifetime; re-pulls are gesture/navigation driven
/// (never a `Timer.periodic`). The section pickers are pure statics so the
/// "which booking goes in which home section" logic unit-tests without a container.
@riverpod
class CustomerHomeController extends _$CustomerHomeController {
  @override
  Future<List<Booking>> build() async {
    // GET /bookings returns rows where customer_id = me OR guard_id = me — i.e. BOTH roles for a
    // dual-role account. The customer surfaces (dashboard + "Hirer history") must show ONLY the
    // user's own hires, never their accepted GUARD jobs, so scope to customer_id = me. `me` is the
    // token subject (the current account) — read raw so it works without a live Session (+ tests).
    final token = await ref.read(appStoreProvider).readAccessToken();
    final me = token != null ? Jwt.subject(token) : null;
    final data = await ref.read(pguardApiProvider).get('/bookings');
    return (data as List)
        .whereType<Map<String, dynamic>>()
        .map(Booking.fromJson)
        .where((b) => me == null || b.customerId == me)
        .toList();
  }

  /// The newest booking still in flight — the "งานที่กำลังดำเนิน" card. `null` if none.
  static Booking? ongoing(List<Booking> all) {
    for (final b in all) {
      if (!BookingLifecycle.isTerminal(b.status)) return b;
    }
    return null;
  }

  /// The newest finished booking — the "การจองล่าสุด" row. `null` if none.
  static Booking? latest(List<Booking> all) {
    for (final b in all) {
      if (BookingLifecycle.isTerminal(b.status)) return b;
    }
    return null;
  }

  /// The most recent booking address with a value (the home header's location line).
  static String? recentAddress(List<Booking> all) {
    for (final b in all) {
      final address = b.address;
      if (address != null && address.trim().isNotEmpty) return address;
    }
    return null;
  }

  /// Gesture-driven re-pull (pull-to-refresh) — never rethrows; the provider state
  /// carries any error for the UI.
  Future<void> refresh() async {
    ref.invalidateSelf();
    try {
      await future;
    } catch (_) {
      // state is AsyncError — the screen degrades to the services grid only.
    }
  }
}

/// Booked total in satang for a listed booking: `base_fee × hours × guard_count + tip`
/// (all server-owned fields). Display only — the charged amount is the payment's.
int bookingTotalSatang(Booking b) => Money.total(
      baseFeeSatang: Money.satangFromString(b.baseFee),
      hours: b.hours ?? 0,
      guardCount: b.guardCount ?? 0,
      tipSatang: Money.satangFromString(b.tip),
    );

/// Short date for the recent-booking row, locale-driven: `2 มิ.ย.` / `2 Jun`. Pure.
String thaiShortDate(DateTime when, {required bool isThai}) {
  const thMonths = [
    'ม.ค.',
    'ก.พ.',
    'มี.ค.',
    'เม.ย.',
    'พ.ค.',
    'มิ.ย.',
    'ก.ค.',
    'ส.ค.',
    'ก.ย.',
    'ต.ค.',
    'พ.ย.',
    'ธ.ค.',
  ];
  const enMonths = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final l = when.toLocal();
  return '${l.day} ${(isThai ? thMonths : enMonths)[l.month - 1]}';
}
