import '../../core/models/auth_models.dart';
import '../../core/models/chat.dart';
import '../../core/models/notification.dart';
import '../../features/call/call_routes.dart';
import '../../features/chat/chat_routes.dart';

/// Resolve a notification to the in-app location its tile should open, or `null` when there is no
/// useful destination (it still marks read on tap). PURE — no Flutter / Riverpod — so the routing
/// table is unit-testable without a navigator. The acting user's [role] picks the right side of a
/// chat conversation (the same user is a guard in one thread, a customer in another) and decides
/// where a booking notification lands: the guard sees their working screen, the customer sees the
/// live-status screen.
///
/// The reference ids come from the notification `payload` (see
/// `services/notification/src/domain/mapping.rs`): `booking_id`, `conversation_id`, `call_id`.
String? notificationTarget(AppNotification n, {required AuthUser? user}) {
  final isGuard = user?.isGuard == true;

  switch (n.type) {
    case NotificationType.chatMessage:
      final cid = n.conversationId;
      if (cid == null) return null;
      return ChatRoutes.conversation(
        cid,
        acting: isGuard ? ChatRole.guard : ChatRole.customer,
        // Navigation-time HINT only: a notification payload carries no booking status, so this
        // is optimistically writable — safe because ChatScreen now SELF-VERIFIES read-only
        // against the server (`chatServerClosedProvider`) and locks the composer if the
        // conversation's booking has actually completed/cancelled.
        readOnly: false,
      );

    case NotificationType.bookingCreated:
      // A NEW-JOB offer is still `requested` (unaccepted). For a guard it must open the OFFER detail
      // (`/guard/job` — JobDetailScreen with the Accept action), NOT the active-job working screen:
      // that screen assumes an ASSIGNED booking and misreads a `requested` job as "completed". The
      // customer just watches their own new booking on the live-status screen.
      final newBid = n.bookingId;
      if (newBid == null) return null;
      return isGuard ? '/guard/job/$newBid' : '/booking/$newBid/live';

    case NotificationType.guardAssigned:
    case NotificationType.guardEnRoute:
    case NotificationType.guardArrived:
    case NotificationType.bookingCompleted:
    case NotificationType.bookingCancelled:
      final bid = n.bookingId;
      if (bid == null) return null;
      // Guard → their active-job working screen; customer → the booking live-status screen.
      return isGuard ? '/guard/active/$bid' : '/booking/$bid/live';

    case NotificationType.system:
      // `system` is a catch-all on the wire: incoming-call notifications carry a `call_id`, while
      // payment / rating / decline / completion notices identify their real kind via the payload's
      // `event_type` (see `services/notification/src/domain/mapping.rs` `build_data`). An incoming
      // call opens the call screen; everything else routes to its most sensible detail screen so the
      // row is no longer a dead tap.
      final callId = n.callId;
      if (callId != null) return CallRoutes.incoming(callId);

      final event = n.payload['event_type'];
      final bid = n.bookingId;
      switch (event is String ? event : null) {
        case 'pguard.events.rating.submitted':
          // A new review is always delivered to the GUARD → their own ratings & reviews list.
          return '/guard/ratings';
        case 'pguard.events.payment.refund_processed':
          // A refund notice (customer) → the booking's completion summary / receipt, where the
          // reconciled cost + refund breakdown lives.
          return bid == null ? null : '/booking/$bid/summary';
        case 'pguard.events.payment.completed':
        case 'pguard.events.booking.completion_requested':
        case 'pguard.events.booking.declined':
          // Booking-scoped notices: the guard lands on their active-job screen, the customer on the
          // booking live-status screen (declined auto-routes on to re-search from there).
          if (bid == null) return null;
          return isGuard ? '/guard/active/$bid' : '/booking/$bid/live';
        default:
          // A truly-unknown / screen-less kind (e.g. an ended/missed call) has no detail to open.
          return null;
      }
  }
}
