import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/models/auth_models.dart';

void main() {
  group('AuthUser.rolesFromJson', () {
    test('parses a clean de-duplicated list of non-empty role strings', () {
      expect(AuthUser.rolesFromJson(['guard', 'customer']),
          ['guard', 'customer']);
      expect(AuthUser.rolesFromJson(['guard', 'guard', '']),
          ['guard'], reason: 'dedup + drop empties');
    });
    test('tolerates a missing / non-list value', () {
      expect(AuthUser.rolesFromJson(null), isEmpty);
      expect(AuthUser.rolesFromJson('guard'), isEmpty);
      expect(AuthUser.rolesFromJson(42), isEmpty);
    });
  });

  group('AuthUser enrolled-set helpers', () {
    test('single-role account: hasMultipleRoles is false, enrolled = [role]', () {
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

    test('the active role is always treated as enrolled, even if roles is empty/stale',
        () {
      const u = AuthUser(userId: 'u', role: 'guard', roles: []);
      expect(u.enrolledRoles, ['guard']);
      expect(u.isEnrolledIn('guard'), isTrue);
      expect(u.hasMultipleRoles, isFalse);
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
    test('reads role + the enrolled roles array (roles or available_roles)', () {
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
