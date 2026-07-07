import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/models/auth_models.dart';

void main() {
  group('AuthUser.rolesFromJson', () {
    test('parses a clean de-duplicated list of non-empty role strings', () {
      expect(
          AuthUser.rolesFromJson(['guard', 'customer']), ['guard', 'customer']);
      expect(AuthUser.rolesFromJson(['guard', 'guard', '']), ['guard'],
          reason: 'dedup + drop empties');
    });
    test('tolerates a missing / non-list value', () {
      expect(AuthUser.rolesFromJson(null), isEmpty);
      expect(AuthUser.rolesFromJson('guard'), isEmpty);
      expect(AuthUser.rolesFromJson(42), isEmpty);
    });
  });

  group('AuthUser enrolled-set helpers', () {
    test('single-role account: hasMultipleRoles is false, enrolled = [role]',
        () {
      const u = AuthUser(userId: 'u', role: 'customer', roles: ['customer']);
      expect(u.hasMultipleRoles, isFalse);
      expect(u.enrolledRoles, ['customer']);
      expect(u.isEnrolledIn('customer'), isTrue);
      expect(u.isEnrolledIn('guard'), isFalse);
    });

    test('dual-role account: hasMultipleRoles is true, both enrolled', () {
      const u =
          AuthUser(userId: 'u', role: 'customer', roles: ['customer', 'guard']);
      expect(u.hasMultipleRoles, isTrue);
      expect(u.isEnrolledIn('guard'), isTrue);
    });

    test(
        'the active role is always treated as enrolled, even if roles is empty/stale',
        () {
      const u = AuthUser(userId: 'u', role: 'guard', roles: []);
      expect(u.enrolledRoles, ['guard']);
      expect(u.isEnrolledIn('guard'), isTrue);
      expect(u.hasMultipleRoles, isFalse);
    });

    test(
        'isPendingIn: a submitted-but-unapproved role is pending, not enrolled',
        () {
      // Customer account that has SUBMITTED a guard profile (awaiting approval).
      const u = AuthUser(
          userId: 'u',
          role: 'customer',
          roles: ['customer'],
          pendingRoles: ['guard']);
      expect(u.isPendingIn('guard'), isTrue, reason: 'submitted, not approved');
      expect(u.isEnrolledIn('guard'), isFalse, reason: 'not approved yet');
      expect(u.isPendingIn('customer'), isFalse, reason: 'already enrolled');
    });

    test(
        'isPendingIn: once a pending role is APPROVED (enrolled), it is no longer pending',
        () {
      // Server approved guard → it appears in `roles` AND (staler) `pendingRoles`; enrolled wins.
      const u = AuthUser(
          userId: 'u',
          role: 'customer',
          roles: ['customer', 'guard'],
          pendingRoles: ['guard']);
      expect(u.isEnrolledIn('guard'), isTrue);
      expect(u.isPendingIn('guard'), isFalse,
          reason: 'enrolled takes precedence over a stale pending flag');
    });

    test('withRoles refreshes both the enrolled and pending sets', () {
      const u = AuthUser(
          userId: 'u',
          role: 'customer',
          roles: ['customer'],
          pendingRoles: ['guard']);
      // Approval landed: guard moves from pending → enrolled.
      final approved = u.withRoles(['customer', 'guard'], pendingRoles: []);
      expect(approved.isEnrolledIn('guard'), isTrue);
      expect(approved.isPendingIn('guard'), isFalse);
    });

    test('withActiveRole swaps the active role, keeps the enrolled set', () {
      const u =
          AuthUser(userId: 'u', role: 'customer', roles: ['customer', 'guard']);
      final g = u.withActiveRole('guard');
      expect(g.role, 'guard');
      expect(g.enrolledRoles, containsAll(['customer', 'guard']));
    });
  });

  group('AuthUser.fromJson (login / me parsing)', () {
    test('reads role + the enrolled roles array (roles or available_roles)',
        () {
      final fromMe = AuthUser.fromJson({
        'user_id': 'u1',
        'role': 'customer',
        'roles': ['customer', 'guard'],
      });
      expect(fromMe.role, 'customer');
      expect(fromMe.hasMultipleRoles, isTrue);

      final fromLogin = AuthUser.fromJson({
        'sub': 'u1',
        'role': 'guard',
        'available_roles': ['guard'],
      });
      expect(fromLogin.role, 'guard');
      expect(fromLogin.hasMultipleRoles, isFalse);
    });
  });
}
