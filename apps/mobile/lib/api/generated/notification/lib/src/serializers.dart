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
import 'package:pguard_notification_api/src/date_serializer.dart';
import 'package:pguard_notification_api/src/model/date.dart';

import 'package:pguard_notification_api/src/model/api_response_envelope.dart';
import 'package:pguard_notification_api/src/model/audience.dart';
import 'package:pguard_notification_api/src/model/audience_counts.dart';
import 'package:pguard_notification_api/src/model/audience_counts200_response.dart';
import 'package:pguard_notification_api/src/model/automation_rule.dart';
import 'package:pguard_notification_api/src/model/broadcast.dart';
import 'package:pguard_notification_api/src/model/broadcast_mode.dart';
import 'package:pguard_notification_api/src/model/broadcast_status.dart';
import 'package:pguard_notification_api/src/model/create_broadcast200_response.dart';
import 'package:pguard_notification_api/src/model/create_broadcast_request.dart';
import 'package:pguard_notification_api/src/model/create_rule200_response.dart';
import 'package:pguard_notification_api/src/model/create_rule_request.dart';
import 'package:pguard_notification_api/src/model/delete_token_request.dart';
import 'package:pguard_notification_api/src/model/error_body.dart';
import 'package:pguard_notification_api/src/model/error_detail.dart';
import 'package:pguard_notification_api/src/model/inline_object.dart';
import 'package:pguard_notification_api/src/model/list_broadcasts200_response.dart';
import 'package:pguard_notification_api/src/model/list_notifications200_response.dart';
import 'package:pguard_notification_api/src/model/list_rules200_response.dart';
import 'package:pguard_notification_api/src/model/mark_as_read200_response.dart';
import 'package:pguard_notification_api/src/model/notification_log.dart';
import 'package:pguard_notification_api/src/model/notification_type.dart';
import 'package:pguard_notification_api/src/model/register_token_request.dart';
import 'package:pguard_notification_api/src/model/send_notification_request.dart';
import 'package:pguard_notification_api/src/model/unread_count.dart';
import 'package:pguard_notification_api/src/model/unread_count200_response.dart';
import 'package:pguard_notification_api/src/model/update_broadcast_request.dart';
import 'package:pguard_notification_api/src/model/update_rule_request.dart';

part 'serializers.g.dart';

@SerializersFor([
  ApiResponseEnvelope,$ApiResponseEnvelope,
  Audience,
  AudienceCounts,
  AudienceCounts200Response,
  AutomationRule,
  Broadcast,
  BroadcastMode,
  BroadcastStatus,
  CreateBroadcast200Response,
  CreateBroadcastRequest,
  CreateRule200Response,
  CreateRuleRequest,
  DeleteTokenRequest,
  ErrorBody,
  ErrorDetail,
  InlineObject,
  ListBroadcasts200Response,
  ListNotifications200Response,
  ListRules200Response,
  MarkAsRead200Response,
  NotificationLog,
  NotificationType,
  RegisterTokenRequest,
  SendNotificationRequest,
  UnreadCount,
  UnreadCount200Response,
  UpdateBroadcastRequest,
  UpdateRuleRequest,
])
Serializers serializers = (_$serializers.toBuilder()
      ..add(ApiResponseEnvelope.serializer)
      ..add(const OneOfSerializer())
      ..add(const AnyOfSerializer())
      ..add(const DateSerializer())
      ..add(Iso8601DateTimeSerializer())
    ).build();

Serializers standardSerializers =
    (serializers.toBuilder()..addPlugin(StandardJsonPlugin())).build();
