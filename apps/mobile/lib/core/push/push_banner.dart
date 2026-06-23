import 'in_app_banner_type.dart';

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

/// The bold one-line TITLE for a foreground push banner, or `null` when the push is not one we
/// banner (mirrors [pushBanner]'s match set). The banner body comes from [pushBanner]; this is the
/// emphasised heading above it (design #82). PURE — no Flutter / Firebase.
String? pushBannerTitle(Map<String, dynamic> data, {required bool isThai}) {
  if (data['type'] == 'incoming_call') {
    return isThai ? 'สายเรียกเข้า' : 'Incoming call';
  }
  final eventType = data['event_type'];
  if (eventType is! String) return null;
  if (eventType == 'pguard.events.chat.message_sent') {
    return isThai ? 'แชท' : 'Chat';
  }
  if (eventType.startsWith('pguard.events.booking.')) {
    return isThai ? 'งานของคุณ' : 'Your booking';
  }
  return null;
}

/// Severity → colour/icon for a foreground push banner (design #82). Maps the push categories:
/// a cancelled booking is an error (red), a completed/arrived booking is success (green), chat is
/// info (blue), an incoming call is a warning-grade attention (amber), other booking updates are
/// info. Defaults to info for anything else. PURE — no Flutter / Firebase.
InAppBannerType pushBannerType(Map<String, dynamic> data) {
  if (data['type'] == 'incoming_call') return InAppBannerType.warning;

  final eventType = data['event_type'];
  if (eventType is! String) return InAppBannerType.info;

  if (eventType == 'pguard.events.chat.message_sent') return InAppBannerType.info;
  if (eventType.endsWith('.cancelled') || eventType.endsWith('.declined')) {
    return InAppBannerType.error;
  }
  if (eventType.endsWith('.completed') || eventType.endsWith('.arrived')) {
    return InAppBannerType.success;
  }
  return InAppBannerType.info;
}
