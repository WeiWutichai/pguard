//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

import 'dart:async';

import 'package:built_value/json_object.dart';
import 'package:built_value/serializer.dart';
import 'package:dio/dio.dart';

import 'package:pguard_chat_api/src/api_util.dart';
import 'package:pguard_chat_api/src/model/error_body.dart';
import 'package:pguard_chat_api/src/model/inline_object3.dart';
import 'package:pguard_chat_api/src/model/set_request_status_request.dart';

class InternalApi {

  final Dio _dio;

  final Serializers _serializers;

  const InternalApi(this._dio, this._serializers);

  /// Push a booking&#39;s lifecycle status onto its conversation(s)
  /// Service-to-service (service-JWT). Booking calls this on a lifecycle change so chat&#39;s denormalized &#x60;request_status&#x60; stays current — which drives the server-side read-only gate (writes to a &#x60;completed&#x60;/&#x60;cancelled&#x60; conversation are rejected). Never reachable from the edge (the gateway blocks &#x60;/internal/&#x60;). Idempotent. (A booking-event consumer — mirroring the presence read-model — is the natural evolution of this push.) 
  ///
  /// Parameters:
  /// * [requestId] - Booking request UUID the conversation is linked to.
  /// * [setRequestStatusRequest] 
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [InlineObject3] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<InlineObject3>> setConversationRequestStatus({ 
    required String requestId,
    required SetRequestStatusRequest setRequestStatusRequest,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/internal/conversations/by-request/{request_id}/status'.replaceAll('{' r'request_id' '}', encodeQueryParameter(_serializers, requestId, const FullType(String)).toString());
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
      const _type = FullType(SetRequestStatusRequest);
      _bodyData = _serializers.serialize(setRequestStatusRequest, specifiedType: _type);

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

    InlineObject3? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(InlineObject3),
      ) as InlineObject3;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<InlineObject3>(
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
