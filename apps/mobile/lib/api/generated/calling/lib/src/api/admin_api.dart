//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

import 'dart:async';

import 'package:built_value/json_object.dart';
import 'package:built_value/serializer.dart';
import 'package:dio/dio.dart';

import 'package:pguard_calling_api/src/api_util.dart';
import 'package:pguard_calling_api/src/model/admin_list_calls200_response.dart';
import 'package:pguard_calling_api/src/model/call_status.dart';
import 'package:pguard_calling_api/src/model/call_type.dart';
import 'package:pguard_calling_api/src/model/error_body.dart';

class AdminApi {

  final Dio _dio;

  final Serializers _serializers;

  const AdminApi(this._dio, this._serializers);

  /// List ALL calls cross-user (role&#x3D;admin, read-only call log)
  /// The admin call log — every call (NOT participant-scoped, unlike &#x60;GET /calls/{id}&#x60;), newest first, optional &#x60;status&#x60;/&#x60;call_type&#x60; filters + limit/offset. Admin only (else 403). The per-call timeline / ICE / signal-quality detail in the design is not persisted (this service is a relay) — that needs a future call-events read model. 
  ///
  /// Parameters:
  /// * [status] 
  /// * [callType] 
  /// * [limit] 
  /// * [offset] 
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [AdminListCalls200Response] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<AdminListCalls200Response>> adminListCalls({ 
    CallStatus? status,
    CallType? callType,
    int? limit = 50,
    int? offset = 0,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/admin/calls';
    final _options = Options(
      method: r'GET',
      headers: <String, dynamic>{
        ...?headers,
      },
      extra: <String, dynamic>{
        'secure': <Map<String, String>>[
          {
            'type': 'http',
            'scheme': 'bearer',
            'name': 'bearerAuth',
          },
        ],
        ...?extra,
      },
      validateStatus: validateStatus,
    );

    final _queryParameters = <String, dynamic>{
      if (status != null) r'status': encodeQueryParameter(_serializers, status, const FullType(CallStatus)),
      if (callType != null) r'call_type': encodeQueryParameter(_serializers, callType, const FullType(CallType)),
      if (limit != null) r'limit': encodeQueryParameter(_serializers, limit, const FullType(int)),
      if (offset != null) r'offset': encodeQueryParameter(_serializers, offset, const FullType(int)),
    };

    final _response = await _dio.request<Object>(
      _path,
      options: _options,
      queryParameters: _queryParameters,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );

    AdminListCalls200Response? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(AdminListCalls200Response),
      ) as AdminListCalls200Response;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<AdminListCalls200Response>(
      data: _responseData,
      headers: _response.headers,
      isRedirect: _response.isRedirect,
      requestOptions: _response.requestOptions,
      redirects: _response.redirects,
      statusCode: _response.statusCode,
      statusMessage: _response.statusMessage,
      extra: _response.extra,
    );
  }

}
