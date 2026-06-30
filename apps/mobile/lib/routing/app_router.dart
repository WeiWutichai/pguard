import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../core/controllers/session_controller.dart';
import '../core/models/auth_models.dart';
import '../core/models/call.dart';
import '../core/models/chat.dart';
import '../core/models/service_catalog.dart';
import '../features/auth/biometric_enroll_screen.dart';
import '../features/auth/captcha_screen.dart';
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
import '../features/booking/bookings_list_screen.dart';
import '../features/booking/cancellation_screen.dart';
import '../features/booking/guard_discovery_screen.dart';
import '../features/booking/guard_map_screen.dart';
import '../features/booking/job_completion_summary_screen.dart';
import '../features/booking/live_status_screen.dart';
import '../features/booking/payment_screen.dart';
import '../features/booking/review_screen.dart';
import '../features/booking/service_detail_screen.dart';
import '../features/booking/service_selection_screen.dart';
import '../features/call/call_screen.dart';
import '../features/guard/active_job_screen.dart';
import '../features/guard/earnings_screen.dart';
import '../features/guard/guard_jobs_screen.dart';
import '../features/guard/guard_navigation_screen.dart';
import '../features/guard/guard_work_history_screen.dart';
import '../features/guard/job_detail_screen.dart';
import '../features/guard/withdraw_screen.dart';
import '../features/home/customer_home_screen.dart';
import '../features/home/guard_home_screen.dart';
import '../features/help/help_screen.dart';
import '../features/notifications/notification_screen.dart';
import '../features/permissions/location_denied_screen.dart';
import '../features/permissions/location_rationale_screen.dart';
import '../features/ratings/guard_ratings_screen.dart';
import '../features/profile/guard_documents_screen.dart';
import '../features/profile/profile_edit_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/splash_screen.dart';
import '../features/wallet/wallet_screen.dart';

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
    redirect: (context, state) =>
        sessionRedirect(ref.read(sessionProvider), state.matchedLocation),
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(
          path: '/auth/phone', builder: (_, __) => const PhoneEntryScreen()),
      // Bot-check step between phone and OTP (the design keeps the phone screen clean).
      GoRoute(path: '/auth/captcha', builder: (_, __) => const CaptchaScreen()),
      GoRoute(path: '/auth/otp', builder: (_, __) => const OtpScreen()),
      GoRoute(path: '/auth/pin', builder: (_, __) => const PinEntryScreen()),
      // Optional biometric enrolment, inserted between PIN-confirm and role-select (design ⑤).
      GoRoute(
          path: '/auth/biometric',
          builder: (_, __) => const BiometricEnrollScreen()),
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
      // System screens: location-permission rationale + denied recovery, and Help/FAQ.
      // `forGuard` (via extra) defaults the rationale's scope radio (guards → Always).
      GoRoute(
        path: '/permissions/location',
        builder: (_, state) =>
            LocationRationaleScreen(forGuard: state.extra == true),
      ),
      GoRoute(
        path: '/permissions/location/denied',
        builder: (_, __) => const LocationDeniedScreen(),
      ),
      GoRoute(path: '/help', builder: (_, __) => const HelpScreen()),
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
          path: '/profile/edit', builder: (_, __) => const ProfileEditScreen()),
      GoRoute(
          path: '/profile/documents',
          builder: (_, __) => const GuardDocumentsScreen()),
      // Bottom-nav tab destinations: customer booking history + wallet, guard earnings.
      GoRoute(
          path: '/bookings-history',
          builder: (_, __) => const BookingsListScreen()),
      GoRoute(path: '/wallet', builder: (_, __) => const WalletScreen()),
      GoRoute(path: '/earnings', builder: (_, __) => const EarningsScreen()),
      // Chat: the conversation list (acting role in `?role=`) + a single conversation
      // (`?role=`/`?readonly=` so a deep link works without `extra`; the counterpart name,
      // when known, rides in `extra` for the header).
      GoRoute(
        path: '/chat',
        builder: (context, state) => ChatListScreen(
          actingRole: ChatRole.tryParse(state.uri.queryParameters['role']) ??
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
          // The linked booking + whether it is callable now drive the in-thread call action
          // (absent on a deep link / chat-list open with no booking context → action hidden).
          bookingId: state.uri.queryParameters['booking'],
          callable: state.uri.queryParameters['callable'] == '1',
        ),
      ),
      // Guard-side flow: incoming-job detail + active-job working screen.
      // WebRTC call screen. Outgoing: the entry button starts the call (keepAlive controller)
      // then pushes `/call`. Incoming: a notification/push navigates to `/call?incoming=<callId>`.
      GoRoute(
        path: '/call',
        builder: (context, state) => CallScreen(
          incomingCallId: state.uri.queryParameters['incoming'],
          incomingCallType:
              CallType.tryParse(state.uri.queryParameters['type']),
        ),
      ),
      // Guard's full tabbed jobs list (Pending / Active / Done) — the bottom-nav "งาน" tab.
      GoRoute(
          path: '/guard/jobs', builder: (_, __) => const GuardJobsScreen()),
      // Guard's work history (Completed / Cancelled) — from the profile menu.
      GoRoute(
          path: '/guard/history',
          builder: (_, __) => const GuardWorkHistoryScreen()),
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
      // Guard turn-to-site navigation (full-bleed map) — from the en-route stage.
      GoRoute(
        path: '/guard/active/:id/navigate',
        builder: (context, state) =>
            GuardNavigationScreen(bookingId: state.pathParameters['id']!),
      ),
      // Guard back-out flow (escalation warning + reason + admin notes).
      GoRoute(
        path: '/guard/active/:id/withdraw',
        builder: (context, state) =>
            WithdrawScreen(bookingId: state.pathParameters['id']!),
      ),
      // Customer book-a-guard flow (shared keepAlive BookingFlowController carries state).
      // Two-screen package picker: selection (radio) → detail → form.
      GoRoute(
          path: '/book', builder: (_, __) => const ServiceSelectionScreen()),
      // Package detail. Normally the selected ServiceOption rides in `extra`; for a deep link
      // (no extra) it falls back to a `?id=` lookup against the live catalog (servicesProvider).
      GoRoute(
        path: '/book/detail',
        builder: (context, state) {
          final extra = state.extra;
          if (extra is ServiceOption) {
            return ServiceDetailScreen(service: extra);
          }
          return ServiceDetailResolver(
              serviceId: state.uri.queryParameters['id']);
        },
      ),
      GoRoute(
          path: '/book/form', builder: (_, __) => const BookingFormScreen()),
      GoRoute(
          path: '/book/guards',
          builder: (_, __) => const GuardDiscoveryScreen()),
      // PRE-PAY: the instant a guard accepts, live status routes the customer here to pay the
      // server-computed estimate. The screen posts only `{ booking_id }`; it un-gates the guard's
      // en_route once the payment.completed event sets the booking's `paid_at`.
      GoRoute(
        path: '/booking/:id/pay',
        builder: (context, state) =>
            PaymentScreen(bookingId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/booking/:id/live',
        builder: (context, state) =>
            LiveStatusScreen(bookingId: state.pathParameters['id']!),
      ),
      // Customer cancellation flow (reason → confirm sheet → PUT /bookings/{id}/cancel).
      // `extra` carries what live status already knows (address + display total).
      GoRoute(
        path: '/booking/:id/cancel',
        builder: (context, state) => CancellationScreen(
          bookingId: state.pathParameters['id']!,
          args: state.extra is CancellationArgs
              ? state.extra as CancellationArgs
              : null,
        ),
      ),
      // Customer live-map: where is my assigned guard (entered from the live-status screen).
      GoRoute(
        path: '/booking/:id/map',
        builder: (context, state) =>
            GuardMapScreen(bookingId: state.pathParameters['id']!),
      ),
      // Job-completion summary — reached when the customer APPROVES the guard's completion
      // request (pending_completion → completed). Shows the reconciled cost breakdown, then
      // FORCES the customer on to rate the guard (PopScope blocks skipping it).
      GoRoute(
        path: '/booking/:id/summary',
        builder: (context, state) =>
            JobCompletionSummaryScreen(bookingId: state.pathParameters['id']!),
      ),
      // Customer review of a completed booking (entered from the completion summary, or from
      // live-status when already completed).
      GoRoute(
        path: '/booking/:id/review',
        builder: (context, state) =>
            ReviewScreen(bookingId: state.pathParameters['id']!),
      ),
      // Guard's own "ratings & reviews" screen (entered from the dashboard rating card).
      GoRoute(
          path: '/guard/ratings',
          builder: (_, __) => const GuardRatingsScreen()),
    ],
  );
}

String _homeFor(AuthUser? user) =>
    user?.isGuard == true ? '/home/guard' : '/home/customer';

/// The session-gate redirect, extracted PURE so it is unit-testable without mounting screens.
/// Returns the location to redirect TO, or `null` to allow [loc] as-is. Enforces splash → auth →
/// lock → role dashboard, PLUS the multi-role rules (one phone = one account that can be BOTH guard
/// + customer):
///  - a dual-role login auto-lands on the mode picker (`/auth/role`); a single-role login goes home;
///  - an authenticated user may OPEN the mode picker to switch modes (it is NOT bounced back home);
///  - the add-role flow's profile form / pending screen run under /auth WHILE authenticated;
///  - after a switch, the (now-changed) active role drives [_homeFor].
String? sessionRedirect(SessionState session, String loc) {
  switch (session.status) {
    case SessionStatus.unknown:
      return loc == '/splash' ? null : '/splash';
    case SessionStatus.unauthenticated:
      return loc.startsWith('/auth') ? null : '/auth/phone';
    case SessionStatus.onboardingRole:
      // First segment done (phone→OTP→PIN) but role not chosen: resume at role-select.
      // Allow any /auth/* so the live flow can still go role→profile; bounce elsewhere
      // (e.g. /splash on cold start) to /auth/role.
      return loc.startsWith('/auth') ? null : '/auth/role';
    case SessionStatus.pendingApproval:
      // Registered, not yet approved: stay anywhere in the registration sub-flow
      // (role/profile/pending live under /auth); anything else → the pending screen.
      return loc.startsWith('/auth') ? null : '/auth/pending';
    case SessionStatus.locked:
      return loc == '/lock' ? null : '/lock';
    case SessionStatus.authenticated:
      final user = session.user;
      // The mode picker (`/auth/role`) is reachable WHILE authenticated — it's how an account
      // switches modes / goes back to role-select without logging out, AND how a single-role
      // account ENROLS its second role. Allow ANY authenticated user who explicitly opens it (a
      // multi-role auto-land or either-role switch tap). The post-login AUTO-redirect below still
      // only sends MULTI-role accounts here; single-role accounts land on their home and reach the
      // picker on demand via the "เพิ่มบทบาท / Add role" affordance.
      if (loc == '/auth/role') {
        return null;
      }
      // The add-role flow's profile form + pending screen run under /auth/* WHILE authenticated (the
      // user is enrolling a 2nd role in the background) — allow them so the form isn't bounced
      // straight to home. Everything else under /auth (and splash/lock) is a stale entry point: land
      // on the mode picker for a dual-role account, else the single role's home.
      if (loc == '/auth/register/guard' ||
          loc == '/auth/register/customer' ||
          loc == '/auth/pending') {
        return null;
      }
      if (loc == '/splash' || loc == '/lock' || loc.startsWith('/auth')) {
        return user?.hasMultipleRoles == true ? '/auth/role' : _homeFor(user);
      }
      return null;
  }
}
