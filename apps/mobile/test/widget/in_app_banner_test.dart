import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/push/in_app_banner.dart';

/// Mounts a real overlay via [inAppBannerBuilder] (the same wiring `app.dart` uses) so
/// [showInAppBanner] has a context-free surface to drop top toasts into.
Future<void> _pumpHost(WidgetTester tester) async {
  await tester.pumpWidget(
    const MaterialApp(
      builder: inAppBannerBuilder,
      home: Scaffold(body: Center(child: Text('screen'))),
    ),
  );
}

void main() {
  testWidgets('drops a top toast (title + body) and auto-dismisses after ~4s',
      (tester) async {
    await _pumpHost(tester);

    showInAppBanner('A new job is nearby',
        title: 'New job', type: InAppBannerType.success);
    await tester.pump(); // insert the entry
    await tester.pump(const Duration(milliseconds: 300)); // run the slide-down

    // Both the bold title and the body are shown.
    expect(find.text('New job'), findsOneWidget);
    expect(find.text('A new job is nearby'), findsOneWidget);

    // It is anchored to the TOP: the card sits in the upper portion of the screen.
    final size = tester.getSize(find.byType(MaterialApp));
    final cardTop = tester.getTopLeft(find.text('A new job is nearby')).dy;
    expect(cardTop, lessThan(size.height / 2),
        reason: 'banner should drop from the top, not the bottom');

    // Auto-dismiss: after the ~4s visible window the exit animation runs and the entry is gone.
    await tester.pump(const Duration(seconds: 4)); // fire the auto-dismiss timer
    await tester.pumpAndSettle(); // drain the exit animation + overlay removal
    expect(find.text('A new job is nearby'), findsNothing);
  });

  testWidgets('tapping the card invokes onTap and dismisses', (tester) async {
    await _pumpHost(tester);
    var tapped = false;

    showInAppBanner('Incoming call',
        title: 'Call', type: InAppBannerType.warning, onTap: () => tapped = true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('Incoming call'));
    await tester.pumpAndSettle(); // run the exit animation + overlay removal

    expect(tapped, isTrue);
    expect(find.text('Incoming call'), findsNothing);
  });

  testWidgets('the close affordance dismisses early', (tester) async {
    await _pumpHost(tester);

    showInAppBanner('Booking update', type: InAppBannerType.info);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Booking update'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle(); // run the exit animation + overlay removal
    expect(find.text('Booking update'), findsNothing);
  });

  testWidgets('severity drives the icon (error → error_outline)', (tester) async {
    await _pumpHost(tester);

    showInAppBanner('Booking cancelled', type: InAppBannerType.error);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline), findsNothing);
  });

  testWidgets('a null overlay (key not mounted) is a no-op, never a crash',
      (tester) async {
    // No host pumped → inAppBannerKey.currentState is null.
    expect(() => showInAppBanner('orphan'), returnsNormally);
  });
}
