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
import 'package:pguard_calling_api/src/model/inline_object1.dart';

class AdminApi {

  final Dio _dio;

  final Serializers _serializers;

  const AdminApi(this._dio, this._serializers);

  /// One call&#39;s lifecycle TIMELINE (role&#x3D;admin, call-events read model)
  /// The ordered per-call timeline — the call record plus its lifecycle events in chronological order: milestones (&#x60;ringing&#x60; → &#x60;accepted&#x60;/&#x60;rejected&#x60; → &#x60;connected&#x60; → &#x60;ended&#x60;/&#x60;missed&#x60;, each with &#x60;occurred_at&#x60; + the &#x60;actor_id&#x60; that drove it) plus the signaling steps the relay observes as it forwards frames (&#x60;offer&#x60;/&#x60;answer&#x60;/ &#x60;ice_candidate&#x60; relayed, &#x60;peer_offline&#x60; when the peer had no live socket). Admin only (else 403); a non-existent call → 404.  **NOT included (by design):** media QUALITY — jitter, packet loss, bitrate, MOS. A signaling relay cannot observe these; they require SFU (mediasoup &#x60;getStats&#x60;) / TURN (coturn) statistics, which are not wired into the calling service. The timeline surfaces only what the control + signaling planes actually see. &#x60;detail&#x60; carries small structured metadata about each step (e.g. &#x60;end_reason&#x60;, the relayed &#x60;to&#x60;/&#x60;delivered&#x60;) — never the raw SDP/ICE blob. 
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
  /// Returns a [Future] containing a [Response] with a [InlineObject1] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<InlineObject1>> adminCallEvents({ 
    required String id,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/admin/calls/{id}/events'.replaceAll('{' r'id' '}', encodeQueryParameter(_serializers, id, const FullType(String)).toString());
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

    final _response = await _dio.request<Object>(
      _path,
      options: _options,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );

    InlineObject1? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(InlineObject1),
      ) as InlineObject1;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<InlineObject1>(
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

  /// List ALL calls cross-user (role&#x3D;admin, read-only call log)
  /// The admin call log — every call (NOT participant-scoped, unlike &#x60;GET /calls/{id}&#x60;), newest first, optional &#x60;status&#x60;/&#x60;call_type&#x60; filters + limit/offset. Admin only (else 403). The per-call lifecycle TIMELINE is served by &#x60;GET /admin/calls/{id}/events&#x60;. Media QUALITY (jitter/loss/bitrate) is NOT persisted — a signaling relay can&#39;t observe it; it needs SFU/TURN stats (not wired). See that endpoint&#39;s description. 
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
