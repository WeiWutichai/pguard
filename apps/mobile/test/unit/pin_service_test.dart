import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/controllers/pin_service.dart';

import '../support/fakes.dart';

void main() {
  group('PinService (storage-backed)', () {
    test('setup then verify the same PIN succeeds', () async {
      final store = InMemoryStore();
      final svc = PinService(store: store);
      expect(await svc.setup('135790'), isTrue);
      final out = await svc.verify('135790');
      expect(out.kind, PinOutcomeKind.success);
      expect(store.attempts, 0);
    });

    test('rejects an invalid PIN format at setup', () async {
      final svc = PinService(store: InMemoryStore());
      expect(await svc.setup('12ab'), isFalse);
    });

    test('wrong PIN increments attempts and reports remaining', () async {
      final store = InMemoryStore();
      final svc = PinService(store: store);
      await svc.setup('111111');
      final out = await svc.verify('222222');
      expect(out.kind, PinOutcomeKind.wrong);
      expect(out.attemptsRemaining, 9);
      expect(store.attempts, 1);
    });

    test('locks out after 5 wrong attempts', () async {
      final store = InMemoryStore();
      var now = DateTime.utc(2026, 1, 1, 9, 0, 0);
      final svc = PinService(store: store, clock: () => now);
      await svc.setup('111111');
      PinOutcome? out;
      for (var i = 0; i < 5; i++) {
        out = await svc.verify('000000');
      }
      expect(out!.kind, PinOutcomeKind.lockedOut);
      // While locked, even the correct PIN is refused until the window elapses.
      final duringLock = await svc.verify('111111');
      expect(duringLock.kind, PinOutcomeKind.lockedOut);
      // After the lockout window, the correct PIN works again.
      now = now.add(const Duration(seconds: 61));
      final afterLock = await svc.verify('111111');
      expect(afterLock.kind, PinOutcomeKind.success);
    });

    test('wipes after 10 cumulative wrong attempts', () async {
      final store = InMemoryStore();
      var now = DateTime.utc(2026, 1, 1, 9, 0, 0);
      final svc = PinService(store: store, clock: () => now);
      await svc.setup('111111');
      PinOutcome? out;
      for (var i = 0; i < 10; i++) {
        // Skip past each 60s lockout so we reach 10 cumulative wrong attempts.
        now = now.add(const Duration(seconds: 61));
        out = await svc.verify('000000');
      }
      expect(out!.kind, PinOutcomeKind.wiped);
      expect(store.wiped, isTrue);
    });
  });
}
