/// Location builders for the call route (single source of truth for the path shape the router
/// in `lib/routing/app_router.dart` parses). The [CallController] is a keepAlive singleton, so the
/// outgoing route needs no params (the entry button starts the call before navigating); the
/// incoming route carries the call id in `?incoming=` (delivered via a notification/push).
class CallRoutes {
  const CallRoutes._();

  /// The active (already-started) outgoing call.
  static String outgoing() => '/call';

  /// An incoming call to answer.
  static String incoming(String callId) => '/call?incoming=$callId';
}
