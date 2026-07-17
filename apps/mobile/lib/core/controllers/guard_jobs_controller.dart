import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/booking.dart';
import '../network/api_exception.dart';
import '../network/jwt.dart';
import '../providers.dart';
import 'active_job_controller.dart';
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
    // GET /bookings returns customer_id = me OR guard_id = me (both roles for a dual-role account).
    // The guard's job lists must show ONLY jobs THIS guard is assigned to — not the account's own
    // customer hires — so scope the assigned feed to guard_id = me (the token subject). Open jobs
    // come from the separate /bookings/open feed below.
    final token = await ref.read(appStoreProvider).readAccessToken();
    final me = token != null ? Jwt.subject(token) : null;
    final assignedData = await api.get('/bookings');
    // Fail CLOSED: no resolvable subject → no assigned jobs (never fall through to the unfiltered
    // OR-list, which would leak the account's own customer hires into the guard's job list).
    final assigned = me == null
        ? const <Booking>[]
        : (assignedData as List)
            .whereType<Map<String, dynamic>>()
            .map(Booking.fromJson)
            .where((b) => b.guardId == me)
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

  /// Jobs the guard has taken and is/should be working. Terminal states
  /// (`cancelled`/`completed`/`declined`) are explicitly excluded via
  /// [BookingLifecycle.isTerminal] so a job the customer just CANCELLED can never linger in the
  /// active tab and trap the guard there — the whitelist below already omits them, but the guard
  /// makes the intent unmissable and defends against a future status being added to the whitelist.
  static List<Booking> active(List<Booking> all) => all
      .where((b) =>
          !BookingLifecycle.isTerminal(b.status) &&
          (b.status == BookingStatus.accepted ||
              b.status == BookingStatus.enRoute ||
              b.status == BookingStatus.arrived ||
              b.status == BookingStatus.pendingCompletion))
      .toList();

  /// Jobs the guard has finished (the "เสร็จ / Done" tab).
  static List<Booking> completed(List<Booking> all) =>
      all.where((b) => b.status == BookingStatus.completed).toList();

  /// The status badge a job card should carry on the guard's list, or `null` for the normal
  /// in-progress states (accepted/en_route/arrived) that need no extra label. Today only
  /// `pending_completion` gets one: the guard has requested completion and the job now sits in the
  /// active tab awaiting the CUSTOMER's confirmation — without this badge that card is visually
  /// identical to a job the guard should still be working, and finding no "End" action on tap reads
  /// as being stuck. The customer (not the guard) advances it: confirm → `completed` (moves to the
  /// Done tab); reject → `arrived` (back to a normal in-progress card).
  static String? statusBadge(Booking booking, {required bool isThai}) =>
      booking.status == BookingStatus.pendingCompletion
          ? (isThai ? 'รอลูกค้ายืนยันจบงาน' : 'Awaiting customer confirmation')
          : null;

  /// Whether tapping this card should open the READ-ONLY job status view (`/guard/job/{id}`)
  /// instead of the working active-job screen (`/guard/active/{id}`). True for `pending_completion`:
  /// the guard cannot re-end the job (the customer confirms), so the working screen's chrome is
  /// inappropriate — the read-only detail shows the awaiting-confirmation status cleanly. The
  /// genuinely-working states (accepted/en_route/arrived) still open the active screen.
  static bool opensReadOnly(Booking booking) =>
      booking.status == BookingStatus.pendingCompletion;

  /// `POST /v1/bookings/{id}/accept` — first-come accept (sets guard_id = caller).
  ///
  /// On success also invalidates THIS booking's [activeJobControllerProvider] so the active-job
  /// screen the caller navigates to next builds from a FRESH `accepted` snapshot. Without this the
  /// detail screen's still-mounted (autoDispose) read of that provider — fetched while the booking
  /// was `requested` — can be reused across the `context.go`, leaving the active screen showing the
  /// stale `requested` state (wrong stage → no "Go en route" CTA) until a manual refresh.
  Future<String?> accept(String id) => _act(
        () => ref.read(pguardApiProvider).post('/bookings/$id/accept'),
        also: () => ref.invalidate(activeJobControllerProvider(id)),
      );

  /// Pass on an incoming offer the guard isn't taking. SERVER-TRACKED (`POST /bookings/{id}/skip`)
  /// so discovery stops re-offering it to THIS guard — v2 is first-come-accept, so this is a
  /// per-guard skip, NOT a cancellation (the booking stays open for other guards). Removes the card
  /// optimistically for a snappy UI, then persists + re-fetches (so it can't reappear on refresh).
  Future<String?> dismiss(String id) {
    final list = state.valueOrNull;
    if (list != null) {
      state = AsyncData(list.where((b) => b.id != id).toList());
    }
    return _act(() => ref.read(pguardApiProvider).post('/bookings/$id/skip'));
  }

  Future<String?> refresh() async {
    ref.invalidateSelf();
    await future;
    return null;
  }

  /// Runs an action, reloads the list on success. Returns null on success or a user-safe error
  /// message on failure (so the screen can surface it without wiping the loaded list). [also] runs
  /// once on success, after the op but before the list re-fetch, to refresh any RELATED surface
  /// (e.g. the accepted booking's active-job provider).
  Future<String?> _act(Future<dynamic> Function() op,
      {void Function()? also}) async {
    try {
      await op();
      also?.call();
      ref.invalidateSelf();
      await future;
      return null;
    } on ApiException catch (e) {
      // Localize the typed 409 codes the accept/skip path can return (mirrors
      // active_job_controller._localizeApi). The backend ships a machine-readable `code` PLUS an
      // English `message`; a Thai-mode app must surface the Thai copy, not the raw English message.
      final isThai = ref.read(localeControllerProvider) == AppLocale.th;
      switch (e.code) {
        case 'GUARD_BUSY':
          // Guard tried to accept a job overlapping one they already hold.
          return isThai
              ? 'คุณมีงานในช่วงเวลานี้อยู่แล้ว — เลือกงานที่เวลาไม่ทับซ้อนกัน'
              : e.message;
        default:
          return e.message;
      }
    } catch (_) {
      final isThai = ref.read(localeControllerProvider) == AppLocale.th;
      return isThai ? 'เกิดข้อผิดพลาด' : 'Something went wrong';
    }
  }
}
