//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

import 'dart:async';

import 'package:built_value/json_object.dart';
import 'package:built_value/serializer.dart';
import 'package:dio/dio.dart';

import 'package:pguard_chat_api/src/api_util.dart';
import 'package:pguard_chat_api/src/model/admin_list_conversations200_response.dart';
import 'package:pguard_chat_api/src/model/admin_list_messages200_response.dart';
import 'package:pguard_chat_api/src/model/error_body.dart';

class AdminApi {

  final Dio _dio;

  final Serializers _serializers;

  const AdminApi(this._dio, this._serializers);

  /// List ALL conversations cross-user (role&#x3D;admin, read-only)
  /// The admin conversation list — every conversation (NOT participant-scoped, unlike &#x60;GET /conversations&#x60;), newest first, with both participants&#39; names joined + the last message + total count. Admin only (else 403). The message pane reuses &#x60;GET /conversations/{id}/messages&#x60; (admin bypasses the participant gate). Moderation actions (flag/delete/block/archive) in the design have no v2 endpoint. 
  ///
  /// Parameters:
  /// * [limit] 
  /// * [offset] 
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [AdminListConversations200Response] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<AdminListConversations200Response>> adminListConversations({ 
    int? limit = 50,
    int? offset = 0,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/admin/conversations';
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

    AdminListConversations200Response? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(AdminListConversations200Response),
      ) as AdminListConversations200Response;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<AdminListConversations200Response>(
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

  /// ENRICHED message audit for a conversation (role&#x3D;admin, read-only)
  /// The admin moderation/audit message pane. Same newest-first history as &#x60;GET /conversations/{id}/messages&#x60;, but each row is ENRICHED into RENDERABLE data so the web console shows what was ACTUALLY sent — not the raw &#x60;content&#x60; (an attachment UUID for image/video, the pinned call JSON for a &#x60;system&#x60; line). Each message carries a parsed &#x60;kind&#x60; (&#x60;text&#x60; | &#x60;image&#x60; | &#x60;video&#x60; | &#x60;call-event&#x60; | &#x60;system&#x60; | &#x60;unknown&#x60;), the &#x60;text&#x60; for text rows, a resolved &#x60;attachment&#x60; (fresh presigned URL + MIME so the web renders an image thumbnail / video indicator) for media rows, and a structured &#x60;call_event&#x60; for a call-summary &#x60;system&#x60; row. Attachments are resolved in ONE batch query (no N+1) and the bucket is never exposed. Admin only (else 403). READ-ONLY: no moderation actions (Phase D). 
  ///
  /// Parameters:
  /// * [id] - Conversation UUID.
  /// * [limit] - Page size (default 50, max 200).
  /// * [offset] - Rows to skip (default 0).
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [AdminListMessages200Response] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<AdminListMessages200Response>> adminListMessages({ 
    required String id,
    int? limit = 50,
    int? offset = 0,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/admin/conversations/{id}/messages'.replaceAll('{' r'id' '}', encodeQueryParameter(_serializers, id, const FullType(String)).toString());
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

    AdminListMessages200Response? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(AdminListMessages200Response),
      ) as AdminListMessages200Response;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<AdminListMessages200Response>(
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
