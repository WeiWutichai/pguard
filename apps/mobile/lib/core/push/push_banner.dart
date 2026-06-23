/// Decide the in-app banner copy for a FOREGROUND FCM `data` push, or `null` when the push is not
/// one we surface a banner for. PURE (no Flutter / Firebase) so the foreground-banner table is
/// unit-testable without a widget tree.
///
/// The notification service routes two push shapes (see `services/notification/src/domain/
/// mapping.rs`):
///  - the call + new-job pushes carry an explicit `type` (`incoming_call` / `new_job`);
///  - every other persisted notification's push carries `event_type` (the source
///    `pguard.events.*` topic) plus reference ids — but NO `type` field.
/// We classify on whichever is present. `new_job` is handled separately by the registration
/// controller (it also refetches the open-jobs feed), so it is intentionally NOT returned here.
String? pushBanner(Map<String, dynamic> data, {required bool isThai}) {
  final type = data['type'];
  if (type == 'incoming_call') {
    return isThai ? 'สายเรียกเข้า' : 'Incoming call';
  }

  final eventType = data['event_type'];
  if (eventType is! String) return null;

  if (eventType == 'pguard.events.chat.message_sent') {
    return isThai ? 'ข้อความใหม่' : 'New message';
  }
  if (eventType.startsWith('pguard.events.booking.')) {
    return isThai ? 'อัปเดตงานของคุณ' : 'Booking update';
  }
  return null;
}
