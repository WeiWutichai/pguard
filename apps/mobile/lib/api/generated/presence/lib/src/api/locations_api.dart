//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

import 'dart:async';

import 'package:built_value/json_object.dart';
import 'package:built_value/serializer.dart';
import 'package:dio/dio.dart';

import 'package:pguard_presence_api/src/api_util.dart';
import 'package:pguard_presence_api/src/model/error_body.dart';
import 'package:pguard_presence_api/src/model/inline_object.dart';
import 'package:pguard_presence_api/src/model/inline_object1.dart';
import 'package:pguard_presence_api/src/model/inline_object2.dart';
import 'package:pguard_presence_api/src/model/inline_object3.dart';
import 'package:pguard_presence_api/src/model/internal_online_guards200_response.dart';

class LocationsApi {

  final Dio _dio;

  final Serializers _serializers;

  const LocationsApi(this._dio, this._serializers);

  /// Admin route playback — by job (booking) or by guard + time range (#141)
  /// **Admin only.** Returns a guard&#39;s GPS track, OLDEST-first (a replay plays forward in time), in ONE of two mutually-exclusive modes (provide exactly one selector → else &#x60;400&#x60;):    - **by JOB** — &#x60;?booking_id&#x3D;&lt;uuid&gt;&#x60;. The window is derived SERVER-SIDE from the     event-projected assignment: &#x60;started_at&#x60; &#x3D; the &#x60;job_accepted&#x60; event, &#x60;ended_at&#x60; &#x3D; the     terminal event (&#x60;completed&#x60;/&#x60;cancelled&#x60;/&#x60;declined&#x60;), or &#x60;now()&#x60; while the job is still     active (&#x60;window_open&#x3D;true&#x60;). The guard is the one the booking was assigned to.     &#x60;guard_id&#x60;/&#x60;from&#x60;/&#x60;to&#x60; are ignored. &#x60;404&#x60; if the booking was never projected (unknown     id, or a booking with no recorded start/guard).   - **by GUARD** — &#x60;?guard_id&#x3D;&lt;uuid&gt;&amp;from&#x3D;&amp;to&#x3D;&#x60;. That guard&#39;s track in the half-open     &#x60;[from, to)&#x60; window. &#x60;from&#x60;/&#x60;to&#x60; are optional (default: the last 24h ending now); the     span is clamped to 90 days (the retention horizon).  &#x60;limit&#x60; caps the points (default **500** — the #141 cap; hard max **1000**). &#x60;truncated&#x60; is &#x60;true&#x60; when the window holds at least &#x60;limit&#x60; points (narrow the window or raise &#x60;limit&#x60; to the cap to see the rest). Each point carries its &#x60;recorded_at&#x60; timestamp.  **Per-point speed/heading are NOT returned** — &#x60;per_point_speed_heading_available&#x60; is always &#x60;false&#x60;. The append-only &#x60;location_history&#x60; store keeps only lat/lng/accuracy + time; heading/speed are live-only signals (never historized). Flagged, not fabricated.  Reads from the read replica (heavy history scan; admin authz enforced first). 
  ///
  /// Parameters:
  /// * [bookingId] - By-JOB selector. Derives the window from the booking's assignment. Mutually exclusive with `guard_id`.
  /// * [guardId] - By-GUARD selector. Mutually exclusive with `booking_id`.
  /// * [from] - By-GUARD window start (RFC3339, inclusive). Default `to - 24h`. Ignored in by-JOB mode.
  /// * [to] - By-GUARD window end (RFC3339, exclusive). Default now. Ignored in by-JOB mode.
  /// * [limit] - Max points (default 500, capped at 1000).
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [InlineObject3] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<InlineObject3>> adminTrackReplay({ 
    String? bookingId,
    String? guardId,
    DateTime? from,
    DateTime? to,
    int? limit = 500,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/admin/track/replay';
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
      if (bookingId != null) r'booking_id': encodeQueryParameter(_serializers, bookingId, const FullType(String)),
      if (guardId != null) r'guard_id': encodeQueryParameter(_serializers, guardId, const FullType(String)),
      if (from != null) r'from': encodeQueryParameter(_serializers, from, const FullType(DateTime)),
      if (to != null) r'to': encodeQueryParameter(_serializers, to, const FullType(DateTime)),
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

  /// Get a guard&#39;s location history (own / active-booking customer / admin)
  /// Paginated GPS history for guard &#x60;{id}&#x60;, newest first (older than the 90-day PDPA retention window is purged). Same IDOR authz as &#x60;/guards/{id}/location&#x60;. 
  ///
  /// Parameters:
  /// * [id] 
  /// * [limit] - Max points (default 100, capped at 1000).
  /// * [offset] - Pagination offset.
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [InlineObject2] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<InlineObject2>> getGuardHistory({ 
    required String id,
    int? limit = 100,
    int? offset = 0,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/guards/{id}/history'.replaceAll('{' r'id' '}', encodeQueryParameter(_serializers, id, const FullType(String)).toString());
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

  /// Get a guard&#39;s latest location (own / active-booking customer / admin)
  /// Latest known position for guard &#x60;{id}&#x60;. Authz: the guard may read its own; an admin any; a customer ONLY with an active booking with that guard (else &#x60;403&#x60; — no probing unrelated guards). &#x60;404&#x60; if the guard has no recorded location. 
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
  Future<Response<InlineObject1>> getGuardLocation({ 
    required String id,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/guards/{id}/location'.replaceAll('{' r'id' '}', encodeQueryParameter(_serializers, id, const FullType(String)).toString());
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

  /// Live guards + positions (service-to-service)
  /// Internal read for booking&#39;s discovery (&#x60;/available-guards&#x60;) — the guards who are currently OFFERABLE (\&quot;พร้อมรับงาน\&quot;), each with their LATEST fix position. Membership is &#x60;is_online&#x60; ALONE — deliberately NOT gated on GPS freshness: the mobile uplink is movement-gated, so a stationary online guard&#39;s last fix ages past the freshness window while its socket stays up, and a freshness gate here would drop a connected, offerable guard from discovery (bug B). GPS freshness survives only as the green-dot &#x60;is_live&#x60; DISPLAY on the read DTOs, which does not gate this set. Guarded by a **service-JWT** (&#x60;serviceAuth&#x60;, aud &#x60;pguard-internal&#x60;), never reachable from the public edge (the gateway blocks &#x60;/internal/&#x60;). booking uses membership for the online filter AND the coordinates to sort the customer&#39;s list nearest-to-meetup (C2). Narrow projection — id + position only, none of the heading/speed/accuracy the admin &#x60;/locations&#x60; bulk read carries (least-privilege). Documented here for the contract; not part of the user-facing client. 
  ///
  /// Parameters:
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [InternalOnlineGuards200Response] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<InternalOnlineGuards200Response>> internalOnlineGuards({ 
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/internal/online-guards';
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

    InternalOnlineGuards200Response? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(InternalOnlineGuards200Response),
      ) as InternalOnlineGuards200Response;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<InternalOnlineGuards200Response>(
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

  /// List live guard locations (admin only)
  /// Returns the current position of every guard with a recorded location. **Admin only** — a guard or customer receives &#x60;403&#x60; (no bulk pull). &#x60;is_live&#x60; reflects the 5-minute freshness rule; &#x60;?online_only&#x3D;true&#x60; restricts the result to currently-connected guards. 
  ///
  /// Parameters:
  /// * [onlineOnly] - When true, only guards with `is_online = true` are returned.
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [InlineObject] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<InlineObject>> listLocations({ 
    bool? onlineOnly = false,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/locations';
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
      if (onlineOnly != null) r'online_only': encodeQueryParameter(_serializers, onlineOnly, const FullType(bool)),
    };

    final _response = await _dio.request<Object>(
      _path,
      options: _options,
      queryParameters: _queryParameters,
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
