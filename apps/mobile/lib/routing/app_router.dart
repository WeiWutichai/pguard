import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../core/controllers/session_controller.dart';
import '../core/models/auth_models.dart';
import '../core/models/chat.dart';
import '../features/auth/otp_screen.dart';
import '../features/chat/chat_list_screen.dart';
import '../features/chat/chat_screen.dart';
import '../features/auth/phone_entry_screen.dart';
import '../features/auth/pin_entry_screen.dart';
import '../features/auth/pin_lock_screen.dart';
import '../features/auth/registration/customer_registration_screen.dart';
import '../features/auth/registration/guard_registration_screen.dart';
import '../features/auth/registration/registration_pending_screen.dart';
import '../features/auth/registration/role_selection_screen.dart';
import '../features/booking/booking_form_screen.dart';
import '../features/booking/guard_discovery_screen.dart';
import '../features/booking/guard_map_screen.dart';
import '../features/booking/live_status_screen.dart';
import '../features/booking/payment_screen.dart';
import '../features/booking/payment_success_screen.dart';
import '../features/booking/service_selection_screen.dart';
import '../features/call/call_screen.dart';
import '../features/guard/active_job_screen.dart';
import '../features/guard/job_detail_screen.dart';
import '../features/home/customer_home_screen.dart';
import '../features/home/guard_home_screen.dart';
import '../features/notifications/notification_screen.dart';
import '../features/profile/profile_edit_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/splash_screen.dart';

part 'app_router.g.dart';

/// The app router. A single source of truth for navigation; `redirect` enforces the session
/// gate (splash → auth → lock → role dashboard) and re-runs whenever the session changes.
@Riverpod(keepAlive: true)
GoRouter appRouter(AppRouterRef ref) {
  // Bridge Riverpod → go_router: bump a notifier on every session change so redirect re-runs.
  final refresh = ValueNotifier<int>(0);
  ref.listen(sessionProvider, (_, __) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    refreshListenable: refresh,
    initialLocation: '/splash',
    redirect: (context, state) {
      final session = ref.read(sessionProvider);
      final loc = state.matchedLocation;
      switch (session.status) {
        case SessionStatus.unknown:
          return loc == '/splash' ? null : '/splash';
        case SessionStatus.unauthenticated:
          return loc.startsWith('/auth') ? null : '/auth/phone';
        case SessionStatus.pendingApproval:
          // Registered, not yet approved: stay anywhere in the registration sub-flow
          // (role/profile/pending live under /auth); anything else → the pending screen.
          return loc.startsWith('/auth') ? null : '/auth/pending';
        case SessionStatus.locked:
          return loc == '/lock' ? null : '/lock';
        case SessionStatus.authenticated:
          if (loc == '/splash' || loc == '/lock' || loc.startsWith('/auth')) {
            return _homeFor(session.user);
          }
          return null;
      }
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(
          path: '/auth/phone', builder: (_, __) => const PhoneEntryScreen()),
      GoRoute(path: '/auth/otp', builder: (_, __) => const OtpScreen()),
      GoRoute(path: '/auth/pin', builder: (_, __) => const PinEntryScreen()),
      // Registration sub-flow (role-at-register): role → profile form → pending.
      GoRoute(
          path: '/auth/role', builder: (_, __) => const RoleSelectionScreen()),
      GoRoute(
          path: '/auth/register/guard',
          builder: (_, __) => const GuardRegistrationScreen()),
      GoRoute(
          path: '/auth/register/customer',
          builder: (_, __) => const CustomerRegistrationScreen()),
      GoRoute(
          path: '/auth/pending',
          builder: (_, __) => const RegistrationPendingScreen()),
      GoRoute(path: '/lock', builder: (_, __) => const PinLockScreen()),
      GoRoute(
          path: '/home/customer',
          builder: (_, __) => const CustomerHomeScreen()),
      GoRoute(path: '/home/guard', builder: (_, __) => const GuardHomeScreen()),
      // Notification centre + profile/settings (both roles).
      GoRoute(
          path: '/notifications',
          builder: (_, __) => const NotificationScreen()),
      GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
      GoRoute(
          path: '/profile/edit',
          builder: (_, __) => const ProfileEditScreen()),
      // Chat: the conversation list (acting role in `?role=`) + a single conversation
      // (`?role=`/`?readonly=` so a deep link works without `extra`; the counterpart name,
      // when known, rides in `extra` for the header).
      GoRoute(
        path: '/chat',
        builder: (context, state) => ChatListScreen(
          actingRole:
              ChatRole.tryParse(state.uri.queryParameters['role']) ??
                  ChatRole.customer,
        ),
      ),
      GoRoute(
        path: '/chat/c/:id',
        builder: (context, state) => ChatScreen(
          conversationId: state.pathParameters['id']!,
          acting: ChatRole.tryParse(state.uri.queryParameters['role']) ??
              ChatRole.customer,
          readOnly: state.uri.queryParameters['readonly'] == '1',
          title: state.extra is String ? state.extra as String : null,
        ),
      ),
      // Guard-side flow: incoming-job detail + active-job working screen.
      // WebRTC call screen. Outgoing: the entry button starts the call (keepAlive controller)
      // then pushes `/call`. Incoming: a notification/push navigates to `/call?incoming=<callId>`.
      GoRoute(
        path: '/call',
        builder: (context, state) => CallScreen(
          incomingCallId: state.uri.queryParameters['incoming'],
        ),
      ),
      GoRoute(
        path: '/guard/job/:id',
        builder: (context, state) =>
            JobDetailScreen(bookingId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/guard/active/:id',
        builder: (context, state) =>
            ActiveJobScreen(bookingId: state.pathParameters['id']!),
      ),
      // Customer book-a-guard flow (shared keepAlive BookingFlowController carries state).
      GoRoute(path: '/book', builder: (_, __) => const ServiceSelectionScreen()),
      GoRoute(
          path: '/book/form', builder: (_, __) => const BookingFormScreen()),
      GoRoute(
          path: '/book/guards',
          builder: (_, __) => const GuardDiscoveryScreen()),
      GoRoute(
          path: '/book/payment', builder: (_, __) => const PaymentScreen()),
      GoRoute(
          path: '/book/success',
          builder: (_, __) => const PaymentSuccessScreen()),
      GoRoute(
        path: '/booking/:id/live',
        builder: (context, state) =>
            LiveStatusScreen(bookingId: state.pathParameters['id']!),
      ),
      // Customer live-map: where is my assigned guard (entered from the live-status screen).
      GoRoute(
        path: '/booking/:id/map',
        builder: (context, state) =>
            GuardMapScreen(bookingId: state.pathParameters['id']!),
      ),
    ],
  );
}

String _homeFor(AuthUser? user) =>
    user?.isGuard == true ? '/home/guard' : '/home/customer';
