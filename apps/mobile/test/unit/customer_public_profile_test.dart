import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/models/customer_public_profile.dart';

void main() {
  test('parses the lean customer public profile from the wire shape', () {
    final p = CustomerPublicProfile.fromJson({
      'user_id': 'c1',
      'full_name': 'สมหญิง ใจดี',
    });
    expect(p.customerId, 'c1');
    expect(p.fullName, 'สมหญิง ใจดี');
  });

  test('blank/whitespace or absent name → null (never a fabricated name)', () {
    expect(
      CustomerPublicProfile.fromJson({'user_id': 'c1', 'full_name': '   '})
          .fullName,
      isNull,
    );
    expect(CustomerPublicProfile.fromJson({'user_id': 'c1'}).fullName, isNull);
  });

  test('tryParse returns null on a malformed body (degrades to no name)', () {
    expect(CustomerPublicProfile.tryParse(null), isNull);
    expect(CustomerPublicProfile.tryParse('nope'), isNull);
    expect(CustomerPublicProfile.tryParse({'no_user_id': true}), isNull);
  });
}
