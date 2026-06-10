import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'calling/call_engine.dart';
import 'calling/webrtc_call_engine.dart';
import 'controllers/pin_service.dart';
import 'controllers/session_controller.dart';
import 'location/location_service.dart';
import 'media/chat_attachment_service.dart';
import 'media/chat_media_picker.dart';
import 'media/document_picker.dart';
import 'media/photo_capture.dart';
import 'network/api_client.dart';
import 'network/check_in_service.dart';
import 'network/sockets/booking_status_socket.dart';
import 'network/sockets/call_socket.dart';
import 'network/sockets/chat_socket.dart';
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

/// Builds the chat real-time feed (one socket multiplexes all the user's conversations).
/// Production returns a real [ChatSocket] (coded against the chat WS contract); tests override
/// this provider to inject a fake feed.
typedef ChatFeedBuilder = ChatFeed Function(
  Future<String?> Function() tokenProvider,
);

@Riverpod(keepAlive: true)
ChatFeedBuilder chatFeedBuilder(ChatFeedBuilderRef ref) =>
    (tokenProvider) => ChatSocket(tokenProvider: tokenProvider);

/// Picks chat media via the REAL `image_picker` plugin (the same plugin the guard-document
/// picker already uses — no new package). Tests override with a fake (no platform channels).
@Riverpod(keepAlive: true)
ChatMediaPicker chatMediaPicker(ChatMediaPickerRef ref) =>
    ImagePickerChatMediaPicker();

/// Picks + uploads chat attachments (multipart `POST /v1/attachments` through the
/// authenticated Dio client). Tests override with a fake that returns a canned attachment.
@Riverpod(keepAlive: true)
ChatAttachmentService chatAttachmentService(ChatAttachmentServiceRef ref) =>
    ApiChatAttachmentService(
      api: ref.watch(pguardApiProvider),
      picker: ref.watch(chatMediaPickerProvider),
    );

/// Builds a fresh WebRTC engine per call. Production returns a real [WebRtcCallEngine]
/// (flutter_webrtc); tests override this with a factory returning a fake engine (no plugin).
typedef CallEngineFactory = CallEngine Function();

@Riverpod(keepAlive: true)
CallEngineFactory callEngineFactory(CallEngineFactoryRef ref) =>
    WebRtcCallEngine.new;

/// Builds the call-signaling feed (`/ws/call`, Bearer-on-upgrade). Production returns a real
/// [CallSocket]; tests override this provider to inject a fake feed.
typedef CallSignalFeedBuilder = CallSignalFeed Function(
  Future<String?> Function() tokenProvider,
);

@Riverpod(keepAlive: true)
CallSignalFeedBuilder callSignalFeedBuilder(CallSignalFeedBuilderRef ref) =>
    (tokenProvider) => CallSocket(tokenProvider: tokenProvider);

/// Submits hourly check-in progress reports (multipart `POST /v1/bookings/{id}/progress-reports`
/// through the authenticated Dio client). Tests override with a fake that records submissions.
@Riverpod(keepAlive: true)
CheckInService checkInService(CheckInServiceRef ref) =>
    ApiCheckInService(api: ref.watch(pguardApiProvider));

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
