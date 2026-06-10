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
import 'package:pguard_otp_api/src/date_serializer.dart';
import 'package:pguard_otp_api/src/model/date.dart';

import 'package:pguard_otp_api/src/model/api_response_envelope.dart';
import 'package:pguard_otp_api/src/model/error_body.dart';
import 'package:pguard_otp_api/src/model/error_detail.dart';
import 'package:pguard_otp_api/src/model/healthz200_response.dart';
import 'package:pguard_otp_api/src/model/otp_challenge.dart';
import 'package:pguard_otp_api/src/model/otp_challenge200_response.dart';
import 'package:pguard_otp_api/src/model/request_otp200_response.dart';
import 'package:pguard_otp_api/src/model/request_otp_request.dart';
import 'package:pguard_otp_api/src/model/request_otp_result.dart';
import 'package:pguard_otp_api/src/model/verify_otp200_response.dart';
import 'package:pguard_otp_api/src/model/verify_otp_request.dart';
import 'package:pguard_otp_api/src/model/verify_otp_result.dart';

part 'serializers.g.dart';

@SerializersFor([
  ApiResponseEnvelope,$ApiResponseEnvelope,
  ErrorBody,
  ErrorDetail,
  Healthz200Response,
  OtpChallenge,
  OtpChallenge200Response,
  RequestOtp200Response,
  RequestOtpRequest,
  RequestOtpResult,
  VerifyOtp200Response,
  VerifyOtpRequest,
  VerifyOtpResult,
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
