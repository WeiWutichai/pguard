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
import 'package:pguard_profile_api/src/date_serializer.dart';
import 'package:pguard_profile_api/src/model/date.dart';

import 'package:pguard_profile_api/src/model/admin_list_guard_profiles200_response.dart';
import 'package:pguard_profile_api/src/model/api_response_envelope.dart';
import 'package:pguard_profile_api/src/model/approval_status.dart';
import 'package:pguard_profile_api/src/model/customer_profile.dart';
import 'package:pguard_profile_api/src/model/error_body.dart';
import 'package:pguard_profile_api/src/model/error_detail.dart';
import 'package:pguard_profile_api/src/model/get_my_profile200_response.dart';
import 'package:pguard_profile_api/src/model/guard_profile.dart';
import 'package:pguard_profile_api/src/model/inline_object.dart';
import 'package:pguard_profile_api/src/model/inline_object1.dart';
import 'package:pguard_profile_api/src/model/internal_guard.dart';
import 'package:pguard_profile_api/src/model/internal_list_guards200_response.dart';
import 'package:pguard_profile_api/src/model/my_customer_profile.dart';
import 'package:pguard_profile_api/src/model/my_guard_profile.dart';
import 'package:pguard_profile_api/src/model/my_profile.dart';
import 'package:pguard_profile_api/src/model/reject_request.dart';
import 'package:pguard_profile_api/src/model/upsert_customer_profile_request.dart';
import 'package:pguard_profile_api/src/model/upsert_guard_profile_request.dart';

part 'serializers.g.dart';

@SerializersFor([
  AdminListGuardProfiles200Response,
  ApiResponseEnvelope,$ApiResponseEnvelope,
  ApprovalStatus,
  CustomerProfile,$CustomerProfile,
  ErrorBody,
  ErrorDetail,
  GetMyProfile200Response,
  GuardProfile,$GuardProfile,
  InlineObject,
  InlineObject1,
  InternalGuard,
  InternalListGuards200Response,
  MyCustomerProfile,
  MyGuardProfile,
  MyProfile,
  RejectRequest,
  UpsertCustomerProfileRequest,
  UpsertGuardProfileRequest,
])
Serializers serializers = (_$serializers.toBuilder()
      ..add(ApiResponseEnvelope.serializer)
      ..add(CustomerProfile.serializer)
      ..add(GuardProfile.serializer)
      ..add(const OneOfSerializer())
      ..add(const AnyOfSerializer())
      ..add(const DateSerializer())
      ..add(Iso8601DateTimeSerializer())
    ).build();

Serializers standardSerializers =
    (serializers.toBuilder()..addPlugin(StandardJsonPlugin())).build();
