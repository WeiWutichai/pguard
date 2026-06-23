import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../features/call/call_routes.dart';
import '../../routing/app_router.dart';
import '../controllers/guard_jobs_controller.dart';
import '../controllers/locale_controller.dart';
import '../controllers/session_controller.dart';
import '../providers.dart';
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

/// How the push layer surfaces an in-app banner (e.g. "New job nearby"). Default shows a SnackBar
/// over the current screen via the app-wide messenger; overridden in tests to capture the message
/// without a real widget tree.
@riverpod
void Function(String message) pushNotify(PushNotifyRef ref) => showInAppBanner;

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
      _banner(data);
      ref.read(pushNavigateProvider)(CallRoutes.incoming(call.callId));
      return;
    }
    final job = NewJobPush.tryParse(data);
    if (job != null) {
      _onNewJob(); // new_job surfaces its own banner + refetches the open feed
      return;
    }
    // Every other foreground push (booking-status / chat / call) surfaces an in-app banner so the
    // user sees it without leaving the current screen. No `type` field on these — classified by
    // `event_type`. A push we don't recognise yields a null banner and is silently ignored.
    _banner(data);
  }

  /// Surface the in-app banner for a foreground push, if it maps to one (locale-aware).
  void _banner(Map<String, dynamic> data) {
    final isThai = ref.read(localeControllerProvider) == AppLocale.th;
    final message = pushBanner(data, isThai: isThai);
    if (message != null) ref.read(pushNotifyProvider)(message);
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
        isThai ? 'งานใหม่ใกล้คุณ' : 'New job nearby');
  }
}
