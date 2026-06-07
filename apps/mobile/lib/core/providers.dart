import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'controllers/pin_service.dart';
import 'controllers/session_controller.dart';
import 'location/location_service.dart';
import 'media/document_picker.dart';
import 'media/photo_capture.dart';
import 'network/api_client.dart';
import 'network/check_in_service.dart';
import 'network/sockets/booking_status_socket.dart';
import 'network/sockets/presence_socket.dart';
import 'storage/prefs_store.dart';
import 'storage/secure_store.dart' show AppStore, SecureStore;

part 'providers.g.dart';

/// App storage (tokens + PIN + phone). Single instance app-wide; overridden with an in-memory
/// fake in tests (the [AppStore] interface keeps the app off platform channels under test).
@Riverpod(keepAlive: true)
AppStore appStore(AppStoreRef ref) => SecureStore();

/// Non-sensitive preferences (language). Overridden with an in-memory fake in tests.
@Riverpod(keepAlive: true)
PrefsStore prefsStore(PrefsStoreRef ref) => const SharedPrefsStore();

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

/// Location/geocoding for the booking map picker. Offline-safe by default; tests (and a future
/// real geocoder) override this provider.
@Riverpod(keepAlive: true)
LocationService locationService(LocationServiceRef ref) =>
    const DefaultLocationService();

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

/// Builds the guard's presence (GPS uplink) feed. Production returns a real [PresenceSocket]
/// (coded against the not-yet-built presence WS contract); tests inject a fake feed.
typedef PresenceFeedBuilder = PresenceFeed Function(
  Future<String?> Function() tokenProvider,
);

@Riverpod(keepAlive: true)
PresenceFeedBuilder presenceFeedBuilder(PresenceFeedBuilderRef ref) =>
    (tokenProvider) => PresenceSocket(tokenProvider: tokenProvider);

/// Submits hourly check-in progress reports. Default fails (the endpoint isn't built — see
/// [CheckInService]); tests override with a fake that records submissions.
@Riverpod(keepAlive: true)
CheckInService checkInService(CheckInServiceRef ref) =>
    const PendingCheckInService();

/// Captures the check-in checkpoint photo. Default is unavailable (no camera plugin wired);
/// tests override with a fake.
@Riverpod(keepAlive: true)
PhotoCaptureService photoCaptureService(PhotoCaptureServiceRef ref) =>
    const UnavailablePhotoCaptureService();

/// Picks guard-registration document images via the REAL `image_picker` plugin. Tests override
/// this with a fake so the guard form is exercisable without platform channels.
@Riverpod(keepAlive: true)
DocumentPicker documentPicker(DocumentPickerRef ref) =>
    ImagePickerDocumentPicker();
