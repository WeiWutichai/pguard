import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pguard_mobile/core/network/api_exception.dart';
import 'package:pguard_mobile/core/providers.dart';
import 'package:pguard_mobile/features/profile/profile_screen.dart';

import '../support/fakes.dart';

/// The customer profile header now uses the SAME editable avatar widget as the guard: it shows the
/// customer's uploaded photo (presigned URL) when set, and falls back to initials before one is
/// uploaded. Both behaviours are driven entirely through the [FakeApi] (the avatar controller
/// resolves the id from `/auth/me` and probes `/profile/customer/{id}/avatar`).
void main() {
  /// A [FakeApi] that satisfies the profile screen's fetches: identity (`/auth/me`), profile
  /// (`/profile/me`, a customer with a name → known initials), and the customer-avatar probe
  /// (returns [avatarUrl] when non-null, else 404 = no avatar yet).
  FakeApi customerApi({String? avatarUrl}) => FakeApi(
        onGet: (path, _) async {
          switch (path) {
            case '/auth/me':
              return {'user_id': 'c1', 'role': 'customer'};
            case '/profile/me':
              return {
                'kind': 'customer',
                'user_id': 'c1',
                'full_name':
                    'นภา ศรี', // UserProfile.initials → "นศ" (first char of each word)
              };
            case '/profile/customer/c1/avatar':
              if (avatarUrl == null) {
                // 404 = no avatar yet → the controller degrades to null (initials fallback).
                throw const ApiException(message: 'not found', statusCode: 404);
              }
              return {'avatar_url': avatarUrl};
            default:
              return null;
          }
        },
      );

  Future<void> pumpProfile(WidgetTester tester, FakeApi api) async {
    final router = GoRouter(
      initialLocation: '/profile',
      routes: [
        GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
        // Destinations the settings rows push to (never navigated in these tests).
        GoRoute(
            path: '/profile/edit',
            builder: (_, __) => const Scaffold(body: SizedBox())),
        GoRoute(
            path: '/help',
            builder: (_, __) => const Scaffold(body: SizedBox())),
      ],
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        pguardApiProvider.overrideWithValue(api),
        appStoreProvider.overrideWithValue(InMemoryStore()..access = 't'),
        prefsStoreProvider.overrideWithValue(FakePrefsStore()),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    // Let the profile + avatar controllers resolve, but do NOT settle the network-image load
    // (the test HTTP client can't fetch the presigned URL — we assert on the widget, not pixels).
    await tester.pump();
    await tester.pump();
  }

  testWidgets('customer with an avatar set → renders the photo (NetworkImage)',
      (tester) async {
    await pumpProfile(tester, customerApi(avatarUrl: 'https://s3/cust-c1.jpg'));

    final images = tester
        .widgetList<Image>(find.byType(Image))
        .where((i) => i.image is NetworkImage)
        .toList();
    expect(images, isNotEmpty);
    expect((images.first.image as NetworkImage).url, 'https://s3/cust-c1.jpg');
  });

  testWidgets('customer with no avatar yet → initials fallback, no photo',
      (tester) async {
    await pumpProfile(tester, customerApi(avatarUrl: null));

    // No network image (nothing uploaded) — the initials monogram stands in.
    expect(
      tester
          .widgetList<Image>(find.byType(Image))
          .where((i) => i.image is NetworkImage),
      isEmpty,
    );
    expect(find.text('นศ'), findsOneWidget); // initials of "นภา ศรี"
  });

  testWidgets(
      'tapping the PHOTO opens the full-screen viewer (not the upload sheet)',
      (tester) async {
    await pumpProfile(tester, customerApi(avatarUrl: 'https://s3/cust-c1.jpg'));

    await tester.tap(find.byType(ClipOval));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    // The zoomable viewer is up; the upload sheet is NOT (that's the camera badge's job).
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.text('ถ่ายรูป'), findsNothing);
    expect(find.text('เลือกจากคลัง'), findsNothing);
  });

  testWidgets('tapping the CAMERA BADGE opens the upload sheet',
      (tester) async {
    await pumpProfile(tester, customerApi(avatarUrl: 'https://s3/cust-c1.jpg'));

    await tester.tap(find.byIcon(Icons.photo_camera));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.text('ถ่ายรูป'), findsOneWidget);
    expect(find.text('เลือกจากคลัง'), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsNothing);
  });

  testWidgets('no photo yet → tapping the avatar still opens the upload sheet',
      (tester) async {
    await pumpProfile(tester, customerApi(avatarUrl: null));

    await tester.tap(find.byType(ClipOval));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    // Nothing to view, so the tap falls back to the upload flow (never a dead tap).
    expect(find.text('ถ่ายรูป'), findsOneWidget);
  });
}
