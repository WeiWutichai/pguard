import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/chat.dart';
import '../network/api_exception.dart';
import '../providers.dart';

part 'chat_attachment_resolver.g.dart';

/// Resolves an attachment id (carried in a media message's `content`) to its [Attachment] with
/// a FRESH presigned download URL (`GET /v1/attachments/{id}` regenerates it, TTL 1h).
///
/// AutoDispose family: the URL lives only in provider memory while bubbles are on screen —
/// it is never written to prefs/secure storage (hard rule: presigned URLs and tokens don't
/// get cached to disk). Each conversation reopen re-resolves, so a stale URL can't be reused.
@riverpod
Future<Attachment> chatAttachment(
    ChatAttachmentRef ref, String attachmentId) async {
  final data =
      await ref.watch(pguardApiProvider).get('/attachments/$attachmentId');
  if (data is! Map<String, dynamic>) {
    throw const ApiException(
        message: 'โหลดไฟล์แนบไม่สำเร็จ / Could not load attachment');
  }
  return Attachment.fromJson(data);
}
