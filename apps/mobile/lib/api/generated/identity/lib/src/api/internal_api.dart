//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

import 'dart:async';

import 'package:built_value/json_object.dart';
import 'package:built_value/serializer.dart';
import 'package:dio/dio.dart';

import 'package:pguard_identity_api/src/api_util.dart';
import 'package:pguard_identity_api/src/model/error_body.dart';
import 'package:pguard_identity_api/src/model/inline_object.dart';
import 'package:pguard_identity_api/src/model/internal_resolve_user_names200_response.dart';
import 'package:pguard_identity_api/src/model/resolve_users_request.dart';

class InternalApi {

  final Dio _dio;

  final Serializers _serializers;

  const InternalApi(this._dio, this._serializers);

  /// Batch-resolve user_ids to { role, display_name } (service-JWT only)
  /// Resolve a batch of &#x60;user_id&#x60;s to &#x60;{ role, display_name }&#x60; for an internal caller. This is identity&#39;s OWN schema, so it answers EVERY role — including ADMINS, who have no profile row (the gap that left admin names blank on the web admin lists / Activity Log #142). The profile service&#39;s &#x60;POST /admin/users/resolve&#x60; resolves guard/customer locally, then calls this for the still-unresolved ids and merges admin names in.  **Requires a service-JWT** (&#x60;serviceAuth&#x60;, audience &#x60;pguard-internal&#x60;); blocked at the public gateway (&#x60;/internal/&#x60;). Returns a MAP keyed by id; unknown/deleted ids are OMITTED. ONLY &#x60;role&#x60; + &#x60;display_name&#x60; — NEVER phone/email. Bounded to 500 ids (a larger batch → 400). 
  ///
  /// Parameters:
  /// * [resolveUsersRequest] 
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [InternalResolveUserNames200Response] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<InternalResolveUserNames200Response>> internalResolveUserNames({ 
    required ResolveUsersRequest resolveUsersRequest,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/internal/users/names';
    final _options = Options(
      method: r'POST',
      headers: <String, dynamic>{
        ...?headers,
      },
      extra: <String, dynamic>{
        'secure': <Map<String, String>>[
          {
            'type': 'http',
            'scheme': 'bearer',
            'name': 'serviceAuth',
          },
        ],
        ...?extra,
      },
      contentType: 'application/json',
      validateStatus: validateStatus,
    );

    dynamic _bodyData;

    try {
      const _type = FullType(ResolveUsersRequest);
      _bodyData = _serializers.serialize(resolveUsersRequest, specifiedType: _type);

    } catch(error, stackTrace) {
      throw DioException(
         requestOptions: _options.compose(
          _dio.options,
          _path,
        ),
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    final _response = await _dio.request<Object>(
      _path,
      data: _bodyData,
      options: _options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );

    InternalResolveUserNames200Response? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(InternalResolveUserNames200Response),
      ) as InternalResolveUserNames200Response;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<InternalResolveUserNames200Response>(
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

  /// Force-revoke all of a user&#39;s tokens (service-JWT only)
  /// Bumps the user&#39;s &#x60;token_revocation_version&#x60; and revokes every outstanding refresh family — instantly invalidating all access + refresh tokens for incident response. **v2:** requires a service-JWT (&#x60;serviceAuth&#x60;, audience &#x60;pguard-internal&#x60;). Also triggered asynchronously by the &#x60;pguard.events.user.compromised&#x60; NATS event. Not routed through the public gateway. 
  ///
  /// Parameters:
  /// * [id] 
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [InlineObject] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<InlineObject>> internalRevokeAll({ 
    required String id,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/internal/users/{id}/revoke-all'.replaceAll('{' r'id' '}', encodeQueryParameter(_serializers, id, const FullType(String)).toString());
    final _options = Options(
      method: r'POST',
      headers: <String, dynamic>{
        ...?headers,
      },
      extra: <String, dynamic>{
        'secure': <Map<String, String>>[
          {
            'type': 'http',
            'scheme': 'bearer',
            'name': 'serviceAuth',
          },
        ],
        ...?extra,
      },
      validateStatus: validateStatus,
    );

    final _response = await _dio.request<Object>(
      _path,
      options: _options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );

    InlineObject? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(InlineObject),
      ) as InlineObject;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<InlineObject>(
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
