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
import 'package:pguard_identity_api/src/date_serializer.dart';
import 'package:pguard_identity_api/src/model/date.dart';

import 'package:pguard_identity_api/src/model/admin_search_users200_response.dart';
import 'package:pguard_identity_api/src/model/api_response_envelope.dart';
import 'package:pguard_identity_api/src/model/change_password200_response.dart';
import 'package:pguard_identity_api/src/model/change_password200_response_all_of_data.dart';
import 'package:pguard_identity_api/src/model/change_password_request.dart';
import 'package:pguard_identity_api/src/model/data_export200_response.dart';
import 'package:pguard_identity_api/src/model/data_export200_response_all_of_data.dart';
import 'package:pguard_identity_api/src/model/data_export200_response_all_of_data_meta.dart';
import 'package:pguard_identity_api/src/model/delete_me200_response.dart';
import 'package:pguard_identity_api/src/model/delete_me200_response_all_of_data.dart';
import 'package:pguard_identity_api/src/model/error_body.dart';
import 'package:pguard_identity_api/src/model/error_detail.dart';
import 'package:pguard_identity_api/src/model/inline_object.dart';
import 'package:pguard_identity_api/src/model/inline_object1.dart';
import 'package:pguard_identity_api/src/model/internal_resolve_user_names200_response.dart';
import 'package:pguard_identity_api/src/model/login_request.dart';
import 'package:pguard_identity_api/src/model/me.dart';
import 'package:pguard_identity_api/src/model/me200_response.dart';
import 'package:pguard_identity_api/src/model/refresh_request.dart';
import 'package:pguard_identity_api/src/model/register202_response.dart';
import 'package:pguard_identity_api/src/model/register_request.dart';
import 'package:pguard_identity_api/src/model/register_result.dart';
import 'package:pguard_identity_api/src/model/resolve_users_request.dart';
import 'package:pguard_identity_api/src/model/resolved_user.dart';
import 'package:pguard_identity_api/src/model/token_pair.dart';
import 'package:pguard_identity_api/src/model/update_me_request.dart';
import 'package:pguard_identity_api/src/model/user_role.dart';
import 'package:pguard_identity_api/src/model/user_search_result.dart';

part 'serializers.g.dart';

@SerializersFor([
  AdminSearchUsers200Response,
  ApiResponseEnvelope,$ApiResponseEnvelope,
  ChangePassword200Response,
  ChangePassword200ResponseAllOfData,
  ChangePasswordRequest,
  DataExport200Response,
  DataExport200ResponseAllOfData,
  DataExport200ResponseAllOfDataMeta,
  DeleteMe200Response,
  DeleteMe200ResponseAllOfData,
  ErrorBody,
  ErrorDetail,
  InlineObject,
  InlineObject1,
  InternalResolveUserNames200Response,
  LoginRequest,
  Me,
  Me200Response,
  RefreshRequest,
  Register202Response,
  RegisterRequest,
  RegisterResult,
  ResolveUsersRequest,
  ResolvedUser,
  TokenPair,
  UpdateMeRequest,
  UserRole,
  UserSearchResult,
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
