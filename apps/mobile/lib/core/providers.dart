import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'calling/call_engine.dart';
import 'calling/webrtc_call_engine.dart';
import 'controllers/biometric_service.dart';
import 'controllers/pin_service.dart';
import 'controllers/session_controller.dart';
import 'location/geolocator_location_service.dart';
import 'location/location_service.dart';
import 'location/place_search_service.dart';
import 'location/routing_service.dart';
import 'media/chat_attachment_service.dart';
import 'media/chat_media_picker.dart';
import 'media/document_picker.dart';
import 'media/photo_capture.dart';
import 'media/slip_picker.dart';
import 'network/api_client.dart';
import 'network/check_in_service.dart';
import 'network/sockets/booking_status_socket.dart';
import 'network/sockets/call_socket.dart';
import 'network/sockets/chat_socket.dart';
import 'network/sockets/presence_socket.dart';
import 'pdf/document_sharer.dart';
import 'permissions/permission_gate.dart';
import 'storage/prefs_store.dart';
import 'storage/secure_store.dart' show AppStore, SecureStore;

part 'providers.g.dart';

/// App storage (tokens + PIN + phone). Single instance app-wide; overridden with an in-memory
/// fake in tests (the [AppStore] interface keeps the app off platform channels under test).
@Riverpod(keepAlive: true)
AppStore appStore(AppStoreRef ref) => SecureStore();

/// The app-bootstrap future — the fresh-install secure-store WIPE (v1 risk 3.2), kicked by `main()`
/// off the first-paint path (perf-review #7) and overridden onto the scope there. The session
/// classifier ([Session]) awaits it BEFORE reading any stored token, so a reinstall can never
/// classify a session from the prior owner's Keychain tokens — the ordering is preserved even though
/// the wipe no longer blocks the splash. The DEFAULT (used in tests) is an already-complete no-op, so
/// unit tests that drive the real [Session] neither hit `SharedPreferences` nor wipe their seeded
/// store. A plain (non-codegen) provider so `main()` can `overrideWithValue` the concrete future.
final appBootstrapProvider =
    Provider<Future<void>>((ref) => Future<void>.value(), name: 'appBootstrap');

/// Non-sensitive preferences (language). Overridden with an in-memory fake in tests.
@Riverpod(keepAlive: true)
PrefsStore prefsStore(PrefsStoreRef ref) => const SharedPrefsStore();

/// The REST client to the `/v1` gateway (Dio + auth interceptors). On unrecoverable refresh
/// failure it drops the session so the router leaves the dashboard (no zombie auth state).
/// The rejection code (e.g. `SESSION_SUPERSEDED` — kicked by a login on another device) is
/// stashed as a one-shot notice so the returning PIN-login screen can explain WHY.
@Riverpod(keepAlive: true)
PguardApi pguardApi(PguardApiRef ref) => ApiClient(
      store: ref.watch(appStoreProvider),
      onAuthLost: ({String? reasonCode}) {
        if (reasonCode != null) {
          ref.read(sessionNoticeProvider.notifier).state = reasonCode;
        }
        ref.read(sessionProvider.notifier).logout();
      },
    );

/// Local PIN gate (salted hash + lockout/wipe policy).
@Riverpod(keepAlive: true)
PinService pinService(PinServiceRef ref) =>
    PinService(store: ref.watch(appStoreProvider));

/// Local biometric gate (fingerprint/Face ID opt-in over the PIN). Production wraps the real
/// `local_auth` plugin; tests override this provider with a fake authenticator (no channels).
@Riverpod(keepAlive: true)
BiometricService biometricService(BiometricServiceRef ref) => BiometricService(
      store: ref.watch(appStoreProvider),
      authenticator: LocalAuthAuthenticator(),
    );

/// Device GPS for the booking map picker + guard tracking — real `geolocator`-backed source
/// (foreground only; reads the permission_handler-granted permission, never prompts). Degrades to
/// null/empty when not granted or GPS is off. Tests override this provider with an in-memory fake.
@Riverpod(keepAlive: true)
LocationService locationService(LocationServiceRef ref) =>
    GeolocatorLocationService(places: ref.watch(placeSearchServiceProvider));

/// OS LOCATION-permission gate (`permission_handler`). Governs only the permission, not the GPS
/// source. Tests override with a fake (no platform channels).
@Riverpod(keepAlive: true)
PermissionGate permissionGate(PermissionGateRef ref) =>
    const DefaultPermissionGate();

/// Forward + reverse geocoding via OpenStreetMap Nominatim (free, no API key) — powers the
/// place-name search field and a map-pinned point's reverse-geocode. External host (NOT the `/v1`
/// gateway), so it uses its own Dio with the mandatory User-Agent. Tests override with a fake.
@Riverpod(keepAlive: true)
PlaceSearchService placeSearchService(PlaceSearchServiceRef ref) =>
    NominatimPlaceSearchService();

/// Road (turn-by-turn) routing via the api-gateway OSRM proxy (`{apiHost}/v1/osrm/...`). The device
/// can't reach OSRM directly on a Thai mobile network but always reaches the VPS, so the gateway
/// proxies it (and owns the primary→mirror failover). Token-gated, so the service threads the same
/// `validAccessToken` the sockets use. Best-effort: returns null on any failure so the caller
/// degrades to the straight-line geo.dart estimate. Tests override with a fake.
@Riverpod(keepAlive: true)
RoutingService routingService(RoutingServiceRef ref) => OsrmRoutingService(
      tokenProvider: ref.watch(pguardApiProvider).validAccessToken,
    );

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

/// Captures the check-in checkpoint photo via the real camera (`image_picker`,
/// `ImageSource.camera`). Tests override with a fake (no platform channels).
@Riverpod(keepAlive: true)
PhotoCaptureService photoCaptureService(PhotoCaptureServiceRef ref) =>
    ImagePickerPhotoCaptureService();

/// Picks guard-registration document images via the REAL `image_picker` plugin. Tests override
/// this with a fake so the guard form is exercisable without platform channels.
@Riverpod(keepAlive: true)
DocumentPicker documentPicker(DocumentPickerRef ref) =>
    ImagePickerDocumentPicker();

/// Picks the customer's PromptPay transfer-SLIP image (gallery/camera) via the REAL `image_picker`
/// plugin. Tests override this with a fake so the slip-pay flow is exercisable without channels.
@Riverpod(keepAlive: true)
SlipPicker slipPicker(SlipPickerRef ref) => ImagePickerSlipPicker();

/// Hands a generated document (the receipt PDF) to the OS: a temp file + the system share sheet,
/// so the customer can save / LINE / mail / print it. Tests override this with a fake, which keeps
/// the download exercisable end-to-end (the PDF is really built) without `path_provider` or
/// `share_plus` platform channels.
@Riverpod(keepAlive: true)
DocumentSharer documentSharer(DocumentSharerRef ref) =>
    const TempFileDocumentSharer();
