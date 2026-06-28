//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

import 'dart:async';

import 'package:built_value/json_object.dart';
import 'package:built_value/serializer.dart';
import 'package:dio/dio.dart';

import 'package:pguard_identity_api/src/api_util.dart';
import 'package:pguard_identity_api/src/model/admin_search_users200_response.dart';
import 'package:pguard_identity_api/src/model/error_body.dart';

class AdminApi {

  final Dio _dio;

  final Serializers _serializers;

  const AdminApi(this._dio, this._serializers);

  /// Search users by name / phone / email / id (role&#x3D;admin,
  /// Finds users across ALL roles for the admin per-user-notify picker. Matches &#x60;q&#x60; case-insensitively against &#x60;display_name&#x60; / &#x60;phone&#x60; / &#x60;email&#x60;, plus an exact id match when &#x60;q&#x60; is a UUID. **Admin only** (non-admin → 403). Returns &#x60;[{ id, role, display_name, phone_masked }]&#x60; — the phone is MASKED (last-4) and NO other PII crosses the wire. &#x60;limit&#x60; is clamped (default 20, max 50). A blank &#x60;q&#x60; returns an empty list (no full-table dump).  Routed at the gateway to **identity** (it knows every role + the admin display name) — a more-specific rule than &#x60;/admin/users/resolve&#x60; → profile. 
  ///
  /// Parameters:
  /// * [q] - Free-text query (name / phone / email / exact id).
  /// * [limit] 
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [AdminSearchUsers200Response] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<AdminSearchUsers200Response>> adminSearchUsers({ 
    String? q,
    int? limit = 20,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/admin/users/search';
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
      if (q != null) r'q': encodeQueryParameter(_serializers, q, const FullType(String)),
      if (limit != null) r'limit': encodeQueryParameter(_serializers, limit, const FullType(int)),
    };

    final _response = await _dio.request<Object>(
      _path,
      options: _options,
      queryParameters: _queryParameters,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );

    AdminSearchUsers200Response? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(AdminSearchUsers200Response),
      ) as AdminSearchUsers200Response;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<AdminSearchUsers200Response>(
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
