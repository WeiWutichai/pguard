import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pguard_mobile/core/media/chat_attachment_service.dart';
import 'package:pguard_mobile/core/media/chat_media_picker.dart';
import 'package:pguard_mobile/core/network/api_exception.dart';

import '../support/fakes.dart';

Map<String, dynamic> attachmentJson() => {
      'id': 'att1',
      'chat_id': 'cv1',
      'file_key': 'chat/cv1/x.jpg',
      'file_url': 'http://minio:9000/chat/cv1/x.jpg?sig=abc',
      'file_size': 1024,
      'mime_type': 'image/jpeg',
      'created_at': '2026-06-10T00:00:00Z',
    };

void main() {
  late Directory tmp;
  late File photo;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('pguard_att_test');
    photo = File('${tmp.path}/photo.jpg')
      ..writeAsBytesSync(List<int>.filled(64, 7));
  });

  tearDown(() => tmp.delete(recursive: true));

  test('pick → multipart POST /attachments → returns the stored Attachment',
      () async {
    final picker = FakeChatMediaPicker(
        media: PickedMedia(
            path: photo.path, mimeType: 'image/jpeg', sizeBytes: 64));
    FormData? sent;
    final api = FakeApi(onPost: (path, data) async {
      expect(path, '/attachments');
      sent = data as FormData;
      return attachmentJson();
    });

    final service = ApiChatAttachmentService(api: api, picker: picker);
    final attachment = await service
        .pickAndUpload('cv1', ChatAttachmentSource.galleryPhoto, isThai: true);

    expect(picker.picks.single, ChatAttachmentSource.galleryPhoto);
    expect(attachment, isNotNull);
    expect(attachment!.id, 'att1');
    expect(attachment.fileUrl, contains('sig=abc'));

    // The multipart form carries the contract fields with the declared MIME.
    final fields = {for (final f in sent!.fields) f.key: f.value};
    expect(fields['conversation_id'], 'cv1');
    final file = sent!.files.single;
    expect(file.key, 'file');
    expect(file.value.filename, 'photo.jpg');
    expect('${file.value.contentType?.type}/${file.value.contentType?.subtype}',
        'image/jpeg');
  });

  test('user cancels the picker → null, and nothing is uploaded', () async {
    final picker = FakeChatMediaPicker(media: null);
    final api = FakeApi(onPost: (_, __) async => fail('must not upload'));

    final service = ApiChatAttachmentService(api: api, picker: picker);
    final attachment = await service
        .pickAndUpload('cv1', ChatAttachmentSource.cameraPhoto, isThai: true);

    expect(attachment, isNull);
    expect(api.calls, isEmpty);
  });

  test('unsupported MIME fails fast client-side (no upload attempt)', () async {
    final picker = FakeChatMediaPicker(
        media: PickedMedia(
            path: '${tmp.path}/a.gif', mimeType: 'image/gif', sizeBytes: 64));
    final api = FakeApi(onPost: (_, __) async => fail('must not upload'));

    final service = ApiChatAttachmentService(api: api, picker: picker);
    await expectLater(
      service.pickAndUpload('cv1', ChatAttachmentSource.galleryPhoto,
          isThai: true),
      throwsA(isA<ApiException>()
          .having((e) => e.message, 'message', 'ชนิดไฟล์ไม่รองรับ')),
    );
    expect(api.calls, isEmpty);
  });

  test('server rejection (size/MIME gate) propagates the friendly ApiException',
      () async {
    final picker = FakeChatMediaPicker(
        media: PickedMedia(
            path: photo.path, mimeType: 'image/jpeg', sizeBytes: 64));
    final api = FakeApi(onPost: (_, __) async {
      throw const ApiException(
          message: 'ไฟล์ใหญ่เกินไป / File too large', statusCode: 400);
    });

    final service = ApiChatAttachmentService(api: api, picker: picker);
    await expectLater(
      service.pickAndUpload('cv1', ChatAttachmentSource.galleryVideo,
          isThai: true),
      throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'statusCode', 400)),
    );
  });

  test('video picks upload with the video MIME', () async {
    final video = File('${tmp.path}/clip.mp4')
      ..writeAsBytesSync(List<int>.filled(64, 9));
    final picker = FakeChatMediaPicker(
        media: PickedMedia(
            path: video.path, mimeType: 'video/mp4', sizeBytes: 64));
    final api = FakeApi(onPost: (_, __) async {
      return attachmentJson()
        ..['mime_type'] = 'video/mp4'
        ..['file_key'] = 'chat/cv1/x.mp4';
    });

    final service = ApiChatAttachmentService(api: api, picker: picker);
    final attachment = await service
        .pickAndUpload('cv1', ChatAttachmentSource.galleryVideo, isThai: true);
    expect(attachment!.mimeType, 'video/mp4');
    expect(attachment.messageType.wire, 'video');
  });

  test(
      'a video over the gateway body cap fails fast with a clear size message '
      '(no doomed POST)', () async {
    // The api-gateway caps POST /attachments at 30 MiB (BodyCap::Chat); a phone video clears that
    // easily. The service must reject BEFORE the network round-trip so the user gets an actionable
    // message instead of the bare-413 "Request failed". (Root cause: the edge BodyCap::Chat carve-out.)
    final big = File('${tmp.path}/big.mp4')..writeAsBytesSync(const <int>[1, 2]);
    final picker = FakeChatMediaPicker(
        media: PickedMedia(
            path: big.path,
            mimeType: 'video/mp4',
            sizeBytes: ChatUploadLimit.maxUploadBytes + 1));
    final api = FakeApi(onPost: (_, __) async => fail('must not POST a too-large file'));

    final service = ApiChatAttachmentService(api: api, picker: picker);
    await expectLater(
      service.pickAndUpload('cv1', ChatAttachmentSource.galleryVideo,
          isThai: false),
      throwsA(isA<ApiException>()
          .having((e) => e.message, 'message', contains('too large'))),
    );
    expect(api.calls, isEmpty, reason: 'rejected before any upload');
  });

  test('a file exactly at the upload limit is allowed through', () async {
    final ok = File('${tmp.path}/ok.mp4')..writeAsBytesSync(const <int>[1, 2]);
    final picker = FakeChatMediaPicker(
        media: PickedMedia(
            path: ok.path,
            mimeType: 'video/mp4',
            sizeBytes: ChatUploadLimit.maxUploadBytes));
    final api = FakeApi(onPost: (_, __) async {
      return attachmentJson()
        ..['mime_type'] = 'video/mp4'
        ..['file_key'] = 'chat/cv1/x.mp4';
    });

    final service = ApiChatAttachmentService(api: api, picker: picker);
    final attachment = await service
        .pickAndUpload('cv1', ChatAttachmentSource.galleryVideo, isThai: true);
    expect(attachment, isNotNull, reason: 'at-limit file uploads');
  });
}
