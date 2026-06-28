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
import 'package:pguard_calling_api/src/date_serializer.dart';
import 'package:pguard_calling_api/src/model/date.dart';

import 'package:pguard_calling_api/src/model/admin_list_calls200_response.dart';
import 'package:pguard_calling_api/src/model/api_response_envelope.dart';
import 'package:pguard_calling_api/src/model/call.dart';
import 'package:pguard_calling_api/src/model/call_event.dart';
import 'package:pguard_calling_api/src/model/call_event_type.dart';
import 'package:pguard_calling_api/src/model/call_status.dart';
import 'package:pguard_calling_api/src/model/call_timeline.dart';
import 'package:pguard_calling_api/src/model/call_type.dart';
import 'package:pguard_calling_api/src/model/end_call_request.dart';
import 'package:pguard_calling_api/src/model/error_body.dart';
import 'package:pguard_calling_api/src/model/error_detail.dart';
import 'package:pguard_calling_api/src/model/ice_config.dart';
import 'package:pguard_calling_api/src/model/ice_server.dart';
import 'package:pguard_calling_api/src/model/initiate_call_request.dart';
import 'package:pguard_calling_api/src/model/inline_object.dart';
import 'package:pguard_calling_api/src/model/inline_object1.dart';
import 'package:pguard_calling_api/src/model/inline_object2.dart';

part 'serializers.g.dart';

@SerializersFor([
  AdminListCalls200Response,
  ApiResponseEnvelope,$ApiResponseEnvelope,
  Call,
  CallEvent,
  CallEventType,
  CallStatus,
  CallTimeline,
  CallType,
  EndCallRequest,
  ErrorBody,
  ErrorDetail,
  IceConfig,
  IceServer,
  InitiateCallRequest,
  InlineObject,
  InlineObject1,
  InlineObject2,
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
