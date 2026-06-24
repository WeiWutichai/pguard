/// Location builders for the call route (single source of truth for the path shape the router
/// in `lib/routing/app_router.dart` parses). The [CallController] is a keepAlive singleton, so the
/// outgoing route needs no params (the entry button starts the call before navigating); the
/// incoming route carries the call id in `?incoming=` (delivered via a notification/push).
class CallRoutes {
  const CallRoutes._();

  /// The active (already-started) outgoing call.
  static String outgoing() => '/call';

  /// An incoming call to answer. [callType] (when the push carried it) is passed as a HINT so the
  /// ring UI can show the video indicator BEFORE `GET /calls/{id}` resolves — the callee must know
  /// it is a video call before answering. Omitted when the push has no `call_type`.
  static String incoming(String callId, {String? callType}) {
    final type = callType == null ? '' : '&type=$callType';
    return '/call?incoming=$callId$type';
  }
}
