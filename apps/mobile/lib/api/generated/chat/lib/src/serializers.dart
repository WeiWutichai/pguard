//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_import

import 'package:one_of_serializer/any_of_serializer.dart';
import 'package:one_of_serializer/one_of_serializer.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/json_object.dart';
import 'package:built_value/serializer.dart';
import 'package:built_value/standard_json_plugin.dart';
import 'package:built_value/iso_8601_date_time_serializer.dart';
import 'package:pguard_chat_api/src/date_serializer.dart';
import 'package:pguard_chat_api/src/model/date.dart';

import 'package:pguard_chat_api/src/model/admin_attachment_view.dart';
import 'package:pguard_chat_api/src/model/admin_call_event.dart';
import 'package:pguard_chat_api/src/model/admin_conversation.dart';
import 'package:pguard_chat_api/src/model/admin_enriched_message.dart';
import 'package:pguard_chat_api/src/model/admin_list_conversations200_response.dart';
import 'package:pguard_chat_api/src/model/admin_list_messages200_response.dart';
import 'package:pguard_chat_api/src/model/attachment.dart';
import 'package:pguard_chat_api/src/model/conversation_response.dart';
import 'package:pguard_chat_api/src/model/create_conversation_request.dart';
import 'package:pguard_chat_api/src/model/enriched_conversation.dart';
import 'package:pguard_chat_api/src/model/error_body.dart';
import 'package:pguard_chat_api/src/model/error_body_error.dart';
import 'package:pguard_chat_api/src/model/inline_object.dart';
import 'package:pguard_chat_api/src/model/inline_object1.dart';
import 'package:pguard_chat_api/src/model/inline_object2.dart';
import 'package:pguard_chat_api/src/model/list_conversations200_response.dart';
import 'package:pguard_chat_api/src/model/list_messages200_response.dart';
import 'package:pguard_chat_api/src/model/message.dart';
import 'package:pguard_chat_api/src/model/message_type.dart';
import 'package:pguard_chat_api/src/model/participant_input.dart';
import 'package:pguard_chat_api/src/model/set_request_status_request.dart';

part 'serializers.g.dart';

@SerializersFor([
  AdminAttachmentView,
  AdminCallEvent,
  AdminConversation,
  AdminEnrichedMessage,
  AdminListConversations200Response,
  AdminListMessages200Response,
  Attachment,
  ConversationResponse,
  CreateConversationRequest,
  EnrichedConversation,
  ErrorBody,
  ErrorBodyError,
  InlineObject,
  InlineObject1,
  InlineObject2,
  ListConversations200Response,
  ListMessages200Response,
  Message,
  MessageType,
  ParticipantInput,
  SetRequestStatusRequest,
])
Serializers serializers = (_$serializers.toBuilder()
      ..add(const OneOfSerializer())
      ..add(const AnyOfSerializer())
      ..add(const DateSerializer())
      ..add(Iso8601DateTimeSerializer())
    ).build();

Serializers standardSerializers =
    (serializers.toBuilder()..addPlugin(StandardJsonPlugin())).build();
