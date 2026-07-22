import '../../config/app_config.dart';
import '../../models/booking.dart';
import 'ws_client.dart';

/// The live booking-status feed the status controller depends on. An interface so the
/// controller is unit-testable against a fake (no real WebSocket); [BookingStatusSocket] is
/// the production implementation.
abstract class BookingStatusFeed {
  /// Status transitions for the subscribed booking.
  Stream<BookingStatusEvent> get events;

  /// Connection-state edges (`true` on (re)connect, `false` on drop). The controller re-pulls the
  /// REST snapshot on each reconnect to recover any status change missed during the gap — the hub
  /// only forwards LIVE events and sends no snapshot on subscribe.
  Stream<bool> get connectionChanges;
  Future<void> connect();
  Future<void> close();
}

/// Typed booking-status subscription over [ReconnectingWebSocket].
///
/// The api-gateway DOES proxy this WS now: it registers `/v1/ws/bookings/{id}` and runs a NATS
/// status hub that fans `pguard.events.booking.*` (incl. the progress-report refresh nudge) out to
/// every connected session. `{wsBaseUrl}` already carries the `/v1` prefix, so the URL below resolves
/// to `…/v1/ws/bookings/{id}`. The resume re-pull on the live screen is now a belt-and-suspenders for
/// a backgrounded socket, not the primary path. Contract:
///
///   URL : `{wsBaseUrl}/ws/bookings/{id}`        (subscription scope = the path)
///   Auth: `Authorization: Bearer <access>`       on the HTTP upgrade (never URL query)
///   Frame: `{ "type":"booking_status", "booking_id", "status", "occurred_at", "guard_id"? }`
///
/// mirrors the calling service's WS auth (Bearer-on-upgrade + participant-only) so the
/// backend side is a thin addition. NO polling: status arrives as server push.
class BookingStatusSocket implements BookingStatusFeed {
  BookingStatusSocket({
    required this.bookingId,
    required Future<String?> Function() tokenProvider,
    WsChannelFactory? factory,
  }) : _ws = factory != null
            ? ReconnectingWebSocket(
                url: _urlFor(bookingId),
                tokenProvider: tokenProvider,
                factory: factory,
              )
            : ReconnectingWebSocket(
                url: _urlFor(bookingId),
                tokenProvider: tokenProvider,
              );

  final String bookingId;
  final ReconnectingWebSocket _ws;

  static Uri _urlFor(String bookingId) =>
      Uri.parse('${AppConfig.wsBaseUrl}/ws/bookings/$bookingId');

  /// Status transitions for THIS booking, parsed from the push frames. Malformed/unknown
  /// frames are filtered out.
  @override
  Stream<BookingStatusEvent> get events => _ws.messages
      .map(BookingStatusEvent.tryParse)
      .where((e) => e != null)
      .cast<BookingStatusEvent>();

  @override
  Stream<bool> get connectionChanges => _ws.connectionChanges;

  @override
  Future<void> connect() => _ws.connect();

  @override
  Future<void> close() => _ws.close();
}
