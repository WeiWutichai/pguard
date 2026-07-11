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
      // `system` covers incoming-call notifications (a call_id rides in the payload) and
      // payment/rating/decline notices. Only the call has a screen to open.
      final callId = n.callId;
      if (callId != null) return CallRoutes.incoming(callId);
      return null;
  }
}
