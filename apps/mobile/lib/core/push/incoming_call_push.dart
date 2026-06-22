/// A decoded "incoming call" FCM data message.
///
/// The notification service maps `pguard.events.calling.initiated` to a push whose `data` carries
/// `{ type: "incoming_call", call_id, call_type, caller_id }` (see
/// `services/notification/src/domain/mapping.rs`). FCM `data` values are ALWAYS strings on the wire.
class IncomingCallPush {
  const IncomingCallPush({
    required this.callId,
    this.callType,
    this.callerId,
  });

  final String callId;
  final String? callType;
  final String? callerId;

  /// Parse an FCM `data` map into an [IncomingCallPush], or `null` when it is not an incoming-call
  /// push (wrong/absent `type`, or no usable `call_id`). Pure — no platform channels — so the push
  /// routing is unit-testable without Firebase.
  static IncomingCallPush? tryParse(Map<String, dynamic> data) {
    if (data['type'] != 'incoming_call') return null;
    final callId = data['call_id'];
    if (callId is! String || callId.isEmpty) return null;
    return IncomingCallPush(
      callId: callId,
      callType: data['call_type'] as String?,
      callerId: data['caller_id'] as String?,
    );
  }
}
