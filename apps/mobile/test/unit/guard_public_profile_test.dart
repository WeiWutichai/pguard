import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/models/guard_public_profile.dart';

void main() {
  test('parses the lean public profile from the wire shape', () {
    final p = GuardPublicProfile.fromJson({
      'user_id': 'g1',
      'full_name': 'ณัฐพล วงศ์ดี',
      'years_of_experience': 7,
    });
    expect(p.guardId, 'g1');
    expect(p.fullName, 'ณัฐพล วงศ์ดี');
    expect(p.yearsOfExperience, 7);
  });

  test('blank/whitespace or absent name → null (never an empty fabricated name)',
      () {
    expect(
      GuardPublicProfile.fromJson({'user_id': 'g1', 'full_name': '   '}).fullName,
      isNull,
    );
    expect(GuardPublicProfile.fromJson({'user_id': 'g1'}).fullName, isNull);
  });

  test('tryParse returns null on a malformed body (degrades to no name)', () {
    expect(GuardPublicProfile.tryParse(null), isNull);
    expect(GuardPublicProfile.tryParse('nope'), isNull);
    expect(GuardPublicProfile.tryParse({'no_user_id': true}), isNull);
  });

  test('initials: two words → first of each; one word → first two; none → null',
      () {
    expect(
      GuardPublicProfile.fromJson(
              {'user_id': 'g1', 'full_name': 'ณัฐพล วงศ์ดี'})
          .initials,
      'ณว',
    );
    expect(
      GuardPublicProfile.fromJson({'user_id': 'g1', 'full_name': 'Somchai'})
          .initials,
      'So',
    );
    expect(GuardPublicProfile.fromJson({'user_id': 'g1'}).initials, isNull);
  });
}
