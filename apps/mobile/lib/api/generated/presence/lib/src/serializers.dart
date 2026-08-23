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
import 'package:pguard_presence_api/src/date_serializer.dart';
import 'package:pguard_presence_api/src/model/date.dart';

import 'package:pguard_presence_api/src/model/api_response_envelope.dart';
import 'package:pguard_presence_api/src/model/error_body.dart';
import 'package:pguard_presence_api/src/model/error_detail.dart';
import 'package:pguard_presence_api/src/model/guard_location.dart';
import 'package:pguard_presence_api/src/model/history_point.dart';
import 'package:pguard_presence_api/src/model/inline_object.dart';
import 'package:pguard_presence_api/src/model/inline_object1.dart';
import 'package:pguard_presence_api/src/model/inline_object2.dart';
import 'package:pguard_presence_api/src/model/inline_object3.dart';
import 'package:pguard_presence_api/src/model/internal_online_guards200_response.dart';
import 'package:pguard_presence_api/src/model/online_guard.dart';
import 'package:pguard_presence_api/src/model/online_guards.dart';
import 'package:pguard_presence_api/src/model/track_replay.dart';

part 'serializers.g.dart';

@SerializersFor([
  ApiResponseEnvelope,$ApiResponseEnvelope,
  ErrorBody,
  ErrorDetail,
  GuardLocation,
  HistoryPoint,
  InlineObject,
  InlineObject1,
  InlineObject2,
  InlineObject3,
  InternalOnlineGuards200Response,
  OnlineGuard,
  OnlineGuards,
  TrackReplay,
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
