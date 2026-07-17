import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart' show VoidCallback;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../features/call/call_routes.dart';
import '../../routing/app_router.dart';
import '../controllers/active_job_controller.dart';
import '../controllers/booking_status_controller.dart';
import '../controllers/call_controller.dart';
import '../controllers/chat_list_controller.dart';
import '../controllers/customer_home_controller.dart';
import '../controllers/guard_jobs_controller.dart';
import '../controllers/locale_controller.dart';
import '../controllers/notification_controller.dart';
import '../controllers/session_controller.dart';
import '../models/chat.dart';
import '../providers.dart';
import 'booking_push.dart';
import 'in_app_banner.dart';
import 'incoming_call_push.dart';
import 'new_job_push.dart';
import 'push_banner.dart';
import 'push_service.dart';

part 'push_registration_controller.g.dart';

/// The device-push port. Overridden with a fake in tests.
@riverpod
PushService pushService(PushServiceRef ref) =>
    FirebasePushService(FirebaseMessaging.instance);

/// How the push layer navigates (e.g. to an incoming call). Default pushes onto the app router;
/// overridden in tests to capture the route without a real navigator.
@riverpod
void Function(String route) pushNavigate(PushNavigateRef ref) =>
    (route) => ref.read(appRouterProvider).push(route);

/// How the push layer surfaces an in-app banner (e.g. "New job nearby"). Default drops a top toast
/// over the current screen via the app-wide overlay; overridden in tests to capture the message
/// (and optional title/type/onTap) without a real widget tree.
typedef InAppNotify = void Function(
  String message, {
  String? title,
  InAppBannerType type,
  VoidCallback? onTap,
});

@riverpod
InAppNotify pushNotify(PushNotifyRef ref) => showInAppBanner;

/// Registers this device's FCM token with the backend (`POST /tokens`) while the session is
/// authenticated, and routes incoming-call pushes to the in-app call screen.
///
/// keepAlive so it survives screen changes; the token is (re)registered on every authenticated
/// transition (the token is device-level but the backend binds it to the logged-in user, so a new
/// login must rebind it). Best-effort throughout — a Firebase/network failure degrades to "no push"
/// and never crashes the app. The message listeners are wired exactly once.
@Riverpod(keepAlive: true)
class PushRegistration extends _$PushRegistration {
  bool _listening = false;

  /// Delay before the single retry re-fetch of the guard's active job after a PAYMENT push — gives
  /// the booking service time to set `paid_at` (set ASYNC off the same event, ~1s later). Settable
  /// so tests can shrink it; production keeps ~1.5s.
  Duration _payRefetchDelay = const Duration(milliseconds: 1500);

  // @visibleForTesting — shrink the post-payment retry delay so tests don't wait ~1.5s.
  set payRefetchDelayForTest(Duration value) => _payRefetchDelay = value;

  @override
  bool build() {
    ref.listen<SessionState>(
      sessionProvider,
      (_, next) {
        if (next.status == SessionStatus.authenticated) {
          _start();
        }
      },
      fireImmediately: true,
    );
    return false; // state is unused — the side effects (registration + routing) are the point.
  }

  Future<void> _start() async {
    final push = ref.read(pushServiceProvider);
    try {
      await push.requestPermission();
      final token = await push.getToken();
      if (token != null) await _register(token);
      if (_listening) return; // wire the streams + initial message exactly once
      _listening = true;
      push.tokenRefreshes.listen(_register);
      push.foregroundMessages.listen(_handle);
      push.openedMessages.listen(_handle);
      final initial = await push.initialMessageData();
      if (initial != null) _handle(initial);
    } catch (_) {
      // Firebase not configured / permission denied / offline → no push (graceful degrade).
    }
  }

  Future<void> _register(String token) async {
    try {
      await ref.read(pguardApiProvider).post(
        '/tokens',
        data: {'token': token, 'device_type': 'android'},
      );
    } catch (_) {
      // Best-effort; an onTokenRefresh or the next authenticated start retries.
    }
  }

  void _handle(Map<String, dynamic> data) {
    final call = IncomingCallPush.tryParse(data);
    if (call != null) {
      // Forward the push's `call_type` (when present) so the ring UI shows the video indicator
      // immediately — before the screen's `GET /calls/{id}` resolves the authoritative type.
      final route = CallRoutes.incoming(call.callId, callType: call.callType);
      // Drop the call banner with a tap-to-(re)open-the-call-screen action, then route now.
      _banner(data, onTap: () => ref.read(pushNavigateProvider)(route));
      ref.read(pushNavigateProvider)(route);
      return;
    }
    // The caller hung up before we answered → clear the incoming ring (WS `bye` fallback). Silent:
    // it dismisses the ring for THIS call_id and shows no banner.
    if (data['type'] == 'call_cancelled') {
      final id = data['call_id'];
      if (id is String && id.isNotEmpty) {
        ref.read(callControllerProvider.notifier).dismissIncoming(id);
      }
      return;
    }
    final job = NewJobPush.tryParse(data);
    if (job != null) {
      _onNewJob(); // new_job surfaces its own banner + refetches the open feed
      _refreshNotificationCenter();
      return;
    }
    // A payment.completed / booking.* push: re-pull THIS booking's live state so a push received
    // while the screen sits on its one initial snapshot picks up the transition (the WS upgrade is
    // not yet proxied at the gateway). For payment in particular this UN-GATES the guard's
    // "Go en route" once `paid_at` lands. Falls through to the banner so the user still sees it.
    final booking = BookingPush.tryParse(data);
    if (booking != null && booking.bookingId.isNotEmpty) {
      _onBookingPush(booking);
    }
    // Every other foreground push (booking-status / chat / call) surfaces an in-app banner so the
    // user sees it without leaving the current screen. No `type` field on these — classified by
    // `event_type`. A push we don't recognise yields a null banner and is silently ignored.
    _banner(data);
    // The notification service ALSO persisted this push as a notification-center item, so refresh
    // the bell badge + any open list so the unread count bumps LIVE (without waiting for the next
    // dashboard focus). Cheap one-shot invalidates of two autoDispose providers — not polling.
    _refreshNotificationCenter();
    // A chat-message push additionally bumps the CHAT unread badge, which is fed by
    // chatListControllerProvider (a one-shot REST fetch; the chat WS is not proxied at the gateway
    // yet, and connects only while a conversation screen is open). Invalidate BOTH roles' lists so
    // the header/entry chat badge catches up live instead of only on a manual re-open. The backend
    // stamps `event_type = pguard.events.chat.message_sent` on chat pushes.
    if (data['event_type'] == 'pguard.events.chat.message_sent') {
      ref.invalidate(chatListControllerProvider(ChatRole.customer));
      ref.invalidate(chatListControllerProvider(ChatRole.guard));
    }
  }

  /// Re-pull the notification badge ([unreadCountProvider]) and, if open, the notification list
  /// ([notificationControllerProvider]) so a freshly-arrived push bumps the bell's unread count
  /// immediately. Safe whether or not either is mounted (unmounted → dispose, next read rebuilds).
  void _refreshNotificationCenter() {
    ref.invalidate(unreadCountProvider);
    ref.invalidate(notificationControllerProvider);
  }

  /// A payment/booking push landed for [push].bookingId: invalidate that booking's live controllers
  /// so a mounted screen re-fetches and reflects the new server truth.
  ///   - [bookingStatusControllerProvider] — the customer's live screen (status + `paid_at`);
  ///   - [activeJobControllerProvider] — the guard's active-job screen (its `isPaid` gate on
  ///     "Go en route"). It is a one-shot REST fetch, so without this it would stay stuck on
  ///     "รอลูกค้าชำระเงิน";
  ///   - [customerHomeControllerProvider] — the customer's DASHBOARD ongoing-job card (the surface
  ///     the customer most likely sits on when a guard accepts). It is a separate one-shot
  ///     `/bookings` list, so without this the card would stay on "กำลังค้นหาเจ้าหน้าที่" even as the
  ///     live screen advances. Family-less, so a plain invalidate re-pulls it;
  ///   - [guardJobsControllerProvider] (#128) — the GUARD's dashboard + "งานของฉัน" list. Its
  ///     "งานที่กำลังทำ / Active" partition includes `pending_completion`, so when the CUSTOMER
  ///     confirms completion (booking → `completed`, which emits `booking.completed` → the
  ///     notification service pushes the GUARD, recipient = guard_id, with this booking_id) the
  ///     just-completed job must LEAVE "กำลังทำ" and move to "เสร็จ" promptly. Without re-pulling
  ///     this one-shot `/bookings` list, the completed job lingers under "กำลังทำ" showing
  ///     "รอลูกค้ายืนยันจบงาน" until the guard manually pulls-to-refresh or backgrounds/resumes
  ///     (the home's resume invalidate is only the fallback). Family-less, so a plain invalidate
  ///     re-pulls it. The guard receives no push for the OTHER parties' booking.* transitions
  ///     (those route to the customer), so this invalidate is effectively a no-op cost there.
  /// Invalidating an autoDispose provider is safe whether or not it is mounted (mounted → refetch;
  /// unmounted → dispose, the next read rebuilds fresh).
  ///
  /// `paid_at` is set ASYNC (the booking service consumes `payment.completed` ~1s after the push
  /// fires), so for a PAYMENT push, if the re-fetched active job is still NOT paid we retry the
  /// fetch ONCE after a short delay ([_payRefetchDelay]). NOT a `Timer.periodic` — a single,
  /// bounded retry.
  void _onBookingPush(BookingPush push) {
    final id = push.bookingId;
    ref.invalidate(bookingStatusControllerProvider(id));
    ref.invalidate(activeJobControllerProvider(id));
    ref.invalidate(customerHomeControllerProvider);
    // #128: refresh the guard's home/jobs active list so a `booking.completed` push (customer
    // confirmed) moves the job out of "กำลังทำ" without a long wait.
    ref.invalidate(guardJobsControllerProvider);
    if (push.isPayment) {
      unawaited(_retryActiveJobIfUnpaid(id));
    }
  }

  /// One bounded re-fetch of the guard's active job after a payment push, to cover the async lag
  /// before `paid_at` is set. Only re-invalidates when the (still-mounted) active job re-read came
  /// back UNPAID — if it is already paid, or the screen has gone (unmounted), there is nothing to do.
  Future<void> _retryActiveJobIfUnpaid(String bookingId) async {
    await Future<void>.delayed(_payRefetchDelay);
    final provider = activeJobControllerProvider(bookingId);
    if (!ref.exists(provider)) return; // screen gone — nothing to refresh
    final paid = ref.read(provider).valueOrNull?.booking.isPaid ?? false;
    if (!paid) ref.invalidate(provider);
  }

  /// Surface the in-app top toast for a foreground push, if it maps to one (locale-aware). The
  /// body copy + bold title + severity colour/icon all derive from the push payload (design #82).
  /// [onTap] lets a banner re-open its target (e.g. an incoming call) when the user taps the card.
  void _banner(Map<String, dynamic> data, {VoidCallback? onTap}) {
    final isThai = ref.read(localeControllerProvider) == AppLocale.th;
    final message = pushBanner(data, isThai: isThai);
    if (message == null) return;
    ref.read(pushNotifyProvider)(
      message,
      title: pushBannerTitle(data, isThai: isThai),
      type: pushBannerType(data),
      onTap: onTap,
    );
  }

  /// A "new_job" push landed: refetch the open-jobs feed so the offer appears in the guard's
  /// "งานรอตอบรับ" list, and surface an in-app banner. Invalidating the (autoDispose) provider is
  /// safe whether or not the dashboard is currently mounted — when listened it refetches, when not
  /// it disposes and the next read rebuilds fresh. A notification TAP (background→foreground) also
  /// routes here: the dashboard is the guard's landing screen, so refresh + banner is the right
  /// surface there too.
  void _onNewJob() {
    ref.invalidate(guardJobsControllerProvider);
    final isThai = ref.read(localeControllerProvider) == AppLocale.th;
    ref.read(pushNotifyProvider)(
      isThai
          ? 'มีงานใหม่ใกล้คุณ แตะเพื่อดู'
          : 'A new job is nearby — tap to view',
      title: isThai ? 'งานใหม่' : 'New job',
      type: InAppBannerType.success,
    );
  }
}
