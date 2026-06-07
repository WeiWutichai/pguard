import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/features/call/widgets/call_controls.dart';

void main() {
  Widget host({
    required bool muted,
    bool speakerOn = false,
    bool showCamera = false,
    VoidCallback? onToggleMute,
    VoidCallback? onEnd,
  }) =>
      MaterialApp(
        home: Scaffold(
          body: CallControls(
            isThai: true,
            muted: muted,
            speakerOn: speakerOn,
            showCamera: showCamera,
            onToggleMute: onToggleMute ?? () {},
            onToggleSpeaker: () {},
            onSwitchCamera: () {},
            onEnd: onEnd ?? () {},
          ),
        ),
      );

  testWidgets('mute reflects state + fires its callback; end fires its callback',
      (tester) async {
    var muted = false;
    var ended = false;
    await tester.pumpWidget(host(
      muted: false,
      onToggleMute: () => muted = true,
      onEnd: () => ended = true,
    ));

    expect(find.byIcon(Icons.mic), findsOneWidget);
    expect(find.byIcon(Icons.mic_off), findsNothing);

    await tester.tap(find.byIcon(Icons.mic));
    expect(muted, isTrue);

    await tester.tap(find.byIcon(Icons.call_end));
    expect(ended, isTrue);
  });

  testWidgets('muted shows mic_off; a video call shows the camera-flip control',
      (tester) async {
    await tester.pumpWidget(host(muted: true, showCamera: true));
    expect(find.byIcon(Icons.mic_off), findsOneWidget);
    expect(find.byIcon(Icons.cameraswitch), findsOneWidget);
  });

  testWidgets('an audio call hides the camera-flip control', (tester) async {
    await tester.pumpWidget(host(muted: false, showCamera: false));
    expect(find.byIcon(Icons.cameraswitch), findsNothing);
  });
}
