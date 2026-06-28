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
import 'package:pguard_chat_api/src/model/inline_object2.dart';
import 'package:pguard_chat_api/src/model/moderation_reason_body.dart';
import 'package:pguard_chat_api/src/model/set_moderation_status_request.dart';

class AdminApi {

  final Dio _dio;

  final Serializers _serializers;

  const AdminApi(this._dio, this._serializers);

  /// Block a user from chat (chat-level ban)
  /// Admin moderation (Phase D, #136/#137). Sets a chat-level block on the user: a blocked user CANNOT send in ANY conversation (enforced server-side in the send path — never trust the client). Audited. Admin only (else 403). IDEMPOTENT: re-blocking an already-blocked user returns &#x60;applied: false&#x60; (still 200). 
  ///
  /// Parameters:
  /// * [userId] - User UUID (the user to block/unblock from chat).
  /// * [moderationReasonBody] 
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [InlineObject2] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<InlineObject2>> adminBlockUser({ 
    required String userId,
    ModerationReasonBody? moderationReasonBody,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/admin/users/{user_id}/block'.replaceAll('{' r'user_id' '}', encodeQueryParameter(_serializers, userId, const FullType(String)).toString());
    final _options = Options(
      method: r'PUT',
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
      contentType: 'application/json',
      validateStatus: validateStatus,
    );

    dynamic _bodyData;

    try {
      const _type = FullType(ModerationReasonBody);
      _bodyData = moderationReasonBody == null ? null : _serializers.serialize(moderationReasonBody, specifiedType: _type);

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

    InlineObject2? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(InlineObject2),
      ) as InlineObject2;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<InlineObject2>(
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
  /// The admin moderation/audit message pane. Same newest-first history as &#x60;GET /conversations/{id}/messages&#x60;, but each row is ENRICHED into RENDERABLE data so the web console shows what was ACTUALLY sent — not the raw &#x60;content&#x60; (an attachment UUID for image/video, the pinned call JSON for a &#x60;system&#x60; line). Each message carries a parsed &#x60;kind&#x60; (&#x60;text&#x60; | &#x60;image&#x60; | &#x60;video&#x60; | &#x60;call-event&#x60; | &#x60;system&#x60; | &#x60;unknown&#x60;), the &#x60;text&#x60; for text rows, a resolved &#x60;attachment&#x60; (fresh presigned URL + MIME so the web renders an image thumbnail / video indicator) for media rows, and a structured &#x60;call_event&#x60; for a call-summary &#x60;system&#x60; row. Attachments are resolved in ONE batch query (no N+1) and the bucket is never exposed. Admin only (else 403). A redacted (soft-deleted) message is SURFACED with &#x60;redacted: true&#x60; and &#x60;kind: redacted&#x60;; its content is suppressed (the original is never re-exposed, even to an admin). The moderation WRITES live at &#x60;DELETE /admin/messages/{id}&#x60;, &#x60;PUT /admin/conversations/{id}/status&#x60;, and &#x60;PUT|DELETE /admin/users/{user_id}/block&#x60;. 
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

  /// Redact (soft-delete) a message
  /// Admin moderation (Phase D, #136/#137). SOFT-deletes a message: it stays in the table (the original content is NEVER hard-deleted — audit/PDPA), but every read path SUPPRESSES its content (substituting &#x60;[message removed by moderator]&#x60;) and the admin audit view marks it &#x60;redacted&#x60;. Who/when/why is recorded on the message row AND in &#x60;chat.moderation_actions&#x60;. Admin only (else 403). IDEMPOTENT: re-redacting an already-redacted message returns &#x60;applied: false&#x60; (still 200, no second audit row). A non-existent message → 404. 
  ///
  /// Parameters:
  /// * [id] - Message UUID (the message to redact).
  /// * [moderationReasonBody] 
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [InlineObject2] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<InlineObject2>> adminRedactMessage({ 
    required String id,
    ModerationReasonBody? moderationReasonBody,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/admin/messages/{id}'.replaceAll('{' r'id' '}', encodeQueryParameter(_serializers, id, const FullType(String)).toString());
    final _options = Options(
      method: r'DELETE',
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
      contentType: 'application/json',
      validateStatus: validateStatus,
    );

    dynamic _bodyData;

    try {
      const _type = FullType(ModerationReasonBody);
      _bodyData = moderationReasonBody == null ? null : _serializers.serialize(moderationReasonBody, specifiedType: _type);

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

    InlineObject2? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(InlineObject2),
      ) as InlineObject2;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<InlineObject2>(
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

  /// Set a conversation&#39;s MODERATION status (archive / reactivate)
  /// Admin moderation (Phase D, #136/#137). Sets the conversation&#39;s &#x60;moderation_status&#x60; (&#x60;active&#x60; | &#x60;archived&#x60;) — DISTINCT from the booking &#x60;request_status&#x60;. Archiving FREEZES the thread to new writes (a second server-side read-only gate, independent of the booking lifecycle); reactivating reopens it. Audited (who/when/why → &#x60;chat.moderation_actions&#x60;). Admin only (else 403). IDEMPOTENT: setting the status it already holds returns &#x60;applied: false&#x60; (still 200). An unknown status → 400; a non-existent conversation → 404. 
  ///
  /// Parameters:
  /// * [id] - Conversation UUID.
  /// * [setModerationStatusRequest] 
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [InlineObject2] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<InlineObject2>> adminSetConversationModerationStatus({ 
    required String id,
    required SetModerationStatusRequest setModerationStatusRequest,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/admin/conversations/{id}/status'.replaceAll('{' r'id' '}', encodeQueryParameter(_serializers, id, const FullType(String)).toString());
    final _options = Options(
      method: r'PUT',
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
      contentType: 'application/json',
      validateStatus: validateStatus,
    );

    dynamic _bodyData;

    try {
      const _type = FullType(SetModerationStatusRequest);
      _bodyData = _serializers.serialize(setModerationStatusRequest, specifiedType: _type);

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

    InlineObject2? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(InlineObject2),
      ) as InlineObject2;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<InlineObject2>(
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

  /// Unblock a user (lift the chat block)
  /// Admin moderation (Phase D, #136/#137). Lifts the user&#39;s active chat block (the block row is retained for audit, never deleted) so they can send again. Audited. Admin only (else 403). IDEMPOTENT: unblocking a user with no active block returns &#x60;applied: false&#x60; (still 200). 
  ///
  /// Parameters:
  /// * [userId] - User UUID (the user to block/unblock from chat).
  /// * [moderationReasonBody] 
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [InlineObject2] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<InlineObject2>> adminUnblockUser({ 
    required String userId,
    ModerationReasonBody? moderationReasonBody,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/admin/users/{user_id}/block'.replaceAll('{' r'user_id' '}', encodeQueryParameter(_serializers, userId, const FullType(String)).toString());
    final _options = Options(
      method: r'DELETE',
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
      contentType: 'application/json',
      validateStatus: validateStatus,
    );

    dynamic _bodyData;

    try {
      const _type = FullType(ModerationReasonBody);
      _bodyData = moderationReasonBody == null ? null : _serializers.serialize(moderationReasonBody, specifiedType: _type);

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

    InlineObject2? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(InlineObject2),
      ) as InlineObject2;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<InlineObject2>(
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
