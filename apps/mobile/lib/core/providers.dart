import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'controllers/pin_service.dart';
import 'controllers/session_controller.dart';
import 'network/api_client.dart';
import 'network/sockets/booking_status_socket.dart';
import 'storage/secure_store.dart' show AppStore, SecureStore;

part 'providers.g.dart';

/// App storage (tokens + PIN). Single instance app-wide; overridden with an in-memory fake
/// in tests (the [AppStore] interface keeps the app off platform channels under test).
@Riverpod(keepAlive: true)
AppStore appStore(AppStoreRef ref) => SecureStore();

/// The REST client to the `/v1` gateway (Dio + auth interceptors). On unrecoverable refresh
/// failure it drops the session so the router leaves the dashboard (no zombie auth state).
@Riverpod(keepAlive: true)
PguardApi pguardApi(PguardApiRef ref) => ApiClient(
      store: ref.watch(appStoreProvider),
      onAuthLost: () => ref.read(sessionProvider.notifier).logout(),
    );

/// Local PIN gate (salted hash + lockout/wipe policy).
@Riverpod(keepAlive: true)
PinService pinService(PinServiceRef ref) =>
    PinService(store: ref.watch(appStoreProvider));

/// Builds a live booking-status feed for a booking id. Production returns a real
/// [BookingStatusSocket]; tests override this provider to inject a fake feed.
typedef BookingStatusFeedBuilder = BookingStatusFeed Function(
  String bookingId,
  Future<String?> Function() tokenProvider,
);

@Riverpod(keepAlive: true)
BookingStatusFeedBuilder bookingStatusFeedBuilder(
        BookingStatusFeedBuilderRef ref) =>
    (bookingId, tokenProvider) =>
        BookingStatusSocket(bookingId: bookingId, tokenProvider: tokenProvider);
