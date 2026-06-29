import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/controllers/session_controller.dart';
import 'package:pguard_mobile/core/models/auth_models.dart';
import 'package:pguard_mobile/routing/app_router.dart';

/// Unit tests for the PURE session-gate redirect — the multi-role landing rules (one phone = one
/// account that can be BOTH guard + customer). No screens are mounted; we drive [sessionRedirect]
/// directly with a seeded [SessionState].
void main() {
  SessionState authed(String active, List<String> roles) => SessionState(
        SessionStatus.authenticated,
        user: AuthUser(userId: 'u1', role: active, roles: roles),
      );

  group('post-login landing', () {
    test('a DUAL-role login auto-lands on the mode picker (/auth/role)', () {
      final s = authed('customer', ['customer', 'guard']);
      // Coming from /splash or /lock or the auth stack → picker.
      expect(sessionRedirect(s, '/splash'), '/auth/role');
      expect(sessionRedirect(s, '/lock'), '/auth/role');
      expect(sessionRedirect(s, '/auth/pin'), '/auth/role');
    });

    test('a SINGLE-role login goes straight to that role home', () {
      final guard = authed('guard', ['guard']);
      expect(sessionRedirect(guard, '/splash'), '/home/guard');
      final customer = authed('customer', ['customer']);
      expect(sessionRedirect(customer, '/lock'), '/home/customer');
    });
  });

  group('the mode picker is reachable while authenticated (not trapped)', () {
    test('a dual-role user may OPEN /auth/role (allowed, not bounced home)', () {
      final s = authed('guard', ['customer', 'guard']);
      expect(sessionRedirect(s, '/auth/role'), isNull);
    });

    test('a single-role user on /auth/role is sent home (no one-option picker)', () {
      final s = authed('customer', ['customer']);
      expect(sessionRedirect(s, '/auth/role'), '/home/customer');
    });
  });

  group('add-role flow runs under /auth while authenticated', () {
    test('the guard/customer profile forms + pending screen are allowed', () {
      final s = authed('customer', ['customer']); // enrolling a 2nd role
      expect(sessionRedirect(s, '/auth/register/guard'), isNull);
      expect(sessionRedirect(s, '/auth/register/customer'), isNull);
      expect(sessionRedirect(s, '/auth/pending'), isNull);
    });
  });

  group('after a switch, the active role drives the home redirect', () {
    test('the home is computed from the (now-changed) active role', () {
      // Switched into guard: a stale /auth entry redirects to the guard picker/home appropriately.
      final guardActive = authed('guard', ['customer', 'guard']);
      // A real home location is allowed (the screen did context.go after the switch).
      expect(sessionRedirect(guardActive, '/home/guard'), isNull);
    });
  });

  test('non-auth app destinations are untouched while authenticated', () {
    final s = authed('customer', ['customer', 'guard']);
    expect(sessionRedirect(s, '/home/customer'), isNull);
    expect(sessionRedirect(s, '/profile'), isNull);
    expect(sessionRedirect(s, '/bookings-history'), isNull);
  });

  group('non-authenticated states are unchanged (regression)', () {
    test('unknown → splash', () {
      expect(sessionRedirect(const SessionState(SessionStatus.unknown), '/home/guard'),
          '/splash');
    });
    test('unauthenticated → phone', () {
      expect(
          sessionRedirect(
              const SessionState(SessionStatus.unauthenticated), '/home/guard'),
          '/auth/phone');
    });
    test('locked → lock', () {
      expect(sessionRedirect(const SessionState(SessionStatus.locked), '/home/guard'),
          '/lock');
    });
    test('pendingApproval stays in the /auth sub-flow', () {
      expect(
          sessionRedirect(
              const SessionState(SessionStatus.pendingApproval), '/auth/pending'),
          isNull);
    });
  });
}
