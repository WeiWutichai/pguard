import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/booking.dart';
import '../network/api_exception.dart';
import '../providers.dart';
import 'locale_controller.dart';

part 'guard_jobs_controller.g.dart';

/// The guard's jobs: their ASSIGNED bookings (`GET /v1/bookings`, active + completed) merged with
/// the OPEN-job discovery feed (`GET /v1/bookings/open` — `requested`, unassigned jobs the guard
/// can claim, guard-only, newest-first). Exposes accept (POST) + local dismiss of incoming offers.
///
/// The two feeds are disjoint (open jobs have `guard_id = null`; assigned have `guard_id = caller`),
/// so concatenating + partitioning by status is collision-free: [incoming] = the open feed,
/// [active]/[completed] = the assigned feed. The discovery fetch is best-effort — a discovery
/// hiccup must never blank the guard's real assigned jobs. (Geo-filtering the discovery feed by the
/// guard's location is a later enhancement; today it is newest-first.)
@riverpod
class GuardJobsController extends _$GuardJobsController {
  @override
  Future<List<Booking>> build() async {
    final api = ref.read(pguardApiProvider);
    final assignedData = await api.get('/bookings');
    final assigned = (assignedData as List)
        .whereType<Map<String, dynamic>>()
        .map(Booking.fromJson)
        .toList();
    // Open-job discovery — best-effort so a failure here leaves the assigned jobs intact.
    var open = <Booking>[];
    try {
      final openData = await api.get('/bookings/open');
      open = (openData as List)
          .whereType<Map<String, dynamic>>()
          .map(Booking.fromJson)
          .toList();
    } catch (_) {
      // Discovery unavailable → show assigned jobs only (incoming list just stays empty).
    }
    return [...open, ...assigned];
  }

  /// Jobs awaiting the guard's acceptance (open requests).
  static List<Booking> incoming(List<Booking> all) =>
      all.where((b) => b.status == BookingStatus.requested).toList();

  /// Jobs the guard has taken and is/should be working.
  static List<Booking> active(List<Booking> all) => all
      .where((b) =>
          b.status == BookingStatus.accepted ||
          b.status == BookingStatus.enRoute ||
          b.status == BookingStatus.arrived ||
          b.status == BookingStatus.pendingCompletion)
      .toList();

  /// Jobs the guard has finished (the "เสร็จ / Done" tab).
  static List<Booking> completed(List<Booking> all) =>
      all.where((b) => b.status == BookingStatus.completed).toList();

  /// `POST /v1/bookings/{id}/accept` — first-come accept (sets guard_id = caller).
  Future<String?> accept(String id) =>
      _act(() => ref.read(pguardApiProvider).post('/bookings/$id/accept'));

  /// Locally hide an incoming offer the guard isn't taking. v2 is first-come-accept: there is
  /// NO server-side "decline" for an unassigned `requested` job (PUT decline is the assigned
  /// guard withdrawing — see [ActiveJobController.withdraw]), so this just removes the card.
  void dismiss(String id) {
    final list = state.valueOrNull;
    if (list == null) return;
    state = AsyncData(list.where((b) => b.id != id).toList());
  }

  Future<String?> refresh() async {
    ref.invalidateSelf();
    await future;
    return null;
  }

  /// Runs an action, reloads the list on success. Returns null on success or a user-safe error
  /// message on failure (so the screen can surface it without wiping the loaded list).
  Future<String?> _act(Future<dynamic> Function() op) async {
    try {
      await op();
      ref.invalidateSelf();
      await future;
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      final isThai = ref.read(localeControllerProvider) == AppLocale.th;
      return isThai ? 'เกิดข้อผิดพลาด' : 'Something went wrong';
    }
  }
}
