import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/models/registration.dart';
import 'package:pguard_mobile/core/providers.dart';
import 'package:pguard_mobile/features/auth/registration/registration_pending_screen.dart';

import '../support/fakes.dart';

void main() {
  testWidgets('renders the submitted (masked) summary + a check-status action',
      (tester) async {
    final prefs = FakePrefsStore();
    // Cold-start path: the masked summary is read from prefs (bank already masked, never full).
    const summary = RegistrationSummary(
      role: RegistrationRole.guard,
      lines: [
        (label: 'เพศ / Gender', value: 'male'),
        (label: 'เลขบัญชี / Account', value: '••••7890'),
      ],
    );
    prefs.values[kRegSummaryKey] = jsonEncode(summary.toJson());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          prefsStoreProvider.overrideWithValue(prefs),
          appStoreProvider.overrideWithValue(InMemoryStore()),
          pguardApiProvider
              .overrideWithValue(FakeApi(onPost: (_, __) async => null)),
        ],
        child: const MaterialApp(home: RegistrationPendingScreen()),
      ),
    );
    await tester.pumpAndSettle(); // let the post-frame prefs load complete

    expect(find.textContaining('Pending approval'), findsOneWidget);
    // The masked account is rendered; the full number is never present.
    expect(find.text('••••7890'), findsOneWidget);
    expect(find.text('male'), findsOneWidget);
    expect(find.text('ตรวจสอบสถานะ / Check status'), findsOneWidget);
  });
}
