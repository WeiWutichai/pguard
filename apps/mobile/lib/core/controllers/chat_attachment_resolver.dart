import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/chat.dart';
import '../network/api_exception.dart';
import '../providers.dart';
import 'locale_controller.dart';

part 'chat_attachment_resolver.g.dart';

/// Resolves an attachment id (carried in a media message's `content`) to its [Attachment] with
/// a FRESH presigned download URL (`GET /v1/attachments/{id}` regenerates it, TTL 1h).
///
/// AutoDispose family: the URL lives only in provider memory while bubbles are on screen —
/// it is never written to prefs/secure storage (hard rule: presigned URLs and tokens don't
/// get cached to disk). Each conversation reopen re-resolves, so a stale URL can't be reused.
/// (Trade-off: a bubble recycled out of a long list re-resolves on scroll-back; correctness
/// over bandwidth until an in-memory media cache is worth it.)
@riverpod
Future<Attachment> chatAttachment(
    ChatAttachmentRef ref, String attachmentId) async {
  final isThai = ref.read(localeControllerProvider) == AppLocale.th;
  final failed = isThai ? 'โหลดไฟล์แนบไม่สำเร็จ' : 'Could not load attachment';
  // The id arrives in a WS frame `content` the COUNTERPART controls — never interpolate an
  // attacker-shaped string into a request path. The contract says attachment ids are UUIDs.
  if (!_uuid.hasMatch(attachmentId)) {
    throw ApiException(message: failed);
  }
  final data =
      await ref.read(pguardApiProvider).get('/attachments/$attachmentId');
  if (data is! Map<String, dynamic>) {
    throw ApiException(message: failed);
  }
  return Attachment.fromJson(data);
}

final RegExp _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
