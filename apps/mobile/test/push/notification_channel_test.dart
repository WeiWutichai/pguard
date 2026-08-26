import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/network/notification_channel.dart';

void main() {
  group('notification channel (N3b — fix Android sound)', () {
    test('channel id EXACTLY matches the server (services/notification fcm.rs)',
        () {
      // The server sends android.notification.channel_id="pguard_alerts_v2"; a mismatch here
      // reintroduces the silent-push bug (Android 8+ drops an unknown channel onto a low-importance,
      // soundless fallback). The "_v2" id cache-busts the old silent "default" channel, whose
      // importance+sound Android froze at first creation.
      expect(kDefaultChannelId, 'pguard_alerts_v2');
    });

    group('shouldPresentForeground', () {
      test('a normal push with a notification block chimes', () {
        expect(
          shouldPresentForeground(type: null, hasNotificationBlock: true),
          isTrue,
        );
        // Check-in reminders / new jobs / payment etc. carry a type + a notification block.
        expect(
          shouldPresentForeground(
              type: 'checkin_due', hasNotificationBlock: true),
          isTrue,
        );
        expect(
          shouldPresentForeground(type: 'new_job', hasNotificationBlock: true),
          isTrue,
        );
      });

      test('a data-only push (no notification block) is silent', () {
        expect(
          shouldPresentForeground(type: 'new_job', hasNotificationBlock: false),
          isFalse,
        );
      });

      test('call-control pushes are NOT re-presented (dedicated in-app UI)',
          () {
        // These drive the call screen / ring dismissal; a tray notification would double up.
        expect(
          shouldPresentForeground(
              type: 'incoming_call', hasNotificationBlock: true),
          isFalse,
        );
        expect(
          shouldPresentForeground(
              type: 'call_cancelled', hasNotificationBlock: true),
          isFalse,
        );
      });
    });
  });
}
