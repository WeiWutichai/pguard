import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/booking.dart';
import '../network/api_exception.dart';
import '../providers.dart';
import 'locale_controller.dart';

part 'guard_jobs_controller.g.dart';

/// The guard's jobs, from `GET /v1/bookings` (the caller's bookings — for a guard, the ones
/// they are assigned to). Exposes accept (POST) + local dismiss of incoming offers.
///
/// BACKEND DEPENDENCY (documented): `GET /v1/bookings` returns only ALREADY-ASSIGNED jobs
/// (`guard_id = caller`); there is NO open-job discovery feed (`requested` jobs with
/// `guard_id = null` never appear here, and there is no `?status=requested`). So the "incoming"
/// list is empty until a guard job-discovery endpoint is added. accept/decline are coded
/// against the real endpoints and proven against a fake here.
@riverpod
class GuardJobsController extends _$GuardJobsController {
  @override
  Future<List<Booking>> build() async {
    final data = await ref.read(pguardApiProvider).get('/bookings');
    return (data as List)
        .whereType<Map<String, dynamic>>()
        .map(Booking.fromJson)
        .toList();
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
