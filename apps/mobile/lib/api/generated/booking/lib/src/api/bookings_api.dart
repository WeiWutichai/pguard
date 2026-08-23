//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

import 'dart:async';

import 'package:built_value/json_object.dart';
import 'package:built_value/serializer.dart';
import 'package:dio/dio.dart';

import 'package:pguard_booking_api/src/api_util.dart';
import 'package:pguard_booking_api/src/model/cancel_booking_request.dart';
import 'package:pguard_booking_api/src/model/create_booking_request.dart';
import 'package:pguard_booking_api/src/model/create_progress_report200_response.dart';
import 'package:pguard_booking_api/src/model/decline_booking_request.dart';
import 'package:pguard_booking_api/src/model/error_body.dart';
import 'package:pguard_booking_api/src/model/inline_object.dart';
import 'package:pguard_booking_api/src/model/list_available_guards200_response.dart';
import 'package:pguard_booking_api/src/model/list_bookings200_response.dart';
import 'package:pguard_booking_api/src/model/list_progress_reports200_response.dart';
import 'package:pguard_booking_api/src/model/list_services200_response.dart';
import 'package:pguard_booking_api/src/model/review_completion_request.dart';
import 'package:pguard_booking_api/src/model/skip_booking200_response.dart';
import 'package:pguard_booking_api/src/model/start_job_request.dart';

class BookingsApi {

  final Dio _dio;

  final Serializers _serializers;

  const BookingsApi(this._dio, this._serializers);

  /// Guard accepts a request
  /// A guard accepts → status &#x60;accepted&#x60;, &#x60;guard_id&#x60; set to the caller. Enqueues &#x60;pguard.events.booking.job_accepted&#x60; &#x60;{ booking_id, customer_id, guard_id }&#x60; into the outbox in the SAME transaction (transactional outbox). Rejected with 409 if the booking is not in a state from which acceptance is legal.  DIRECTED OFFER (C3): if the booking was directed at ONE guard (&#x60;target_guard_id&#x60; set), only that guard may accept — any other guard is rejected with **403 &#x60;NOT_OFFERED_TO_YOU&#x60;** (the app localizes the code). An OPEN booking (&#x60;target_guard_id&#x60; null) stays first-come. 
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
  Future<Response<InlineObject>> acceptBooking({ 
    required String id,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/bookings/{id}/accept'.replaceAll('{' r'id' '}', encodeQueryParameter(_serializers, id, const FullType(String)).toString());
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

  /// Assigned guard has arrived (120m geofence)
  /// Status &#x60;en_route → arrived&#x60;. Enqueues &#x60;pguard.events.booking.arrived&#x60; into the outbox in the same transaction. Assigned guard only; the booking must be &#x60;en_route&#x60;.  **Geofence (G4):** the proximity gate lives HERE now (it used to be on start). The OPTIONAL body carries the guard&#39;s GPS fix at the moment of pressing \&quot;arrived\&quot;. On a booking with site coordinates (&#x60;lat&#x60;/&#x60;lng&#x60; pinned at create) the fix must be within **120m** of the pin, widened by the reported &#x60;accuracy_m&#x60; capped at **30m** (negative/NaN accuracy counts as 0) — otherwise 409 with &#x60;error.code &#x3D; NOT_AT_SITE&#x60; (message carries the measured distance in whole meters). A pinned booking marked arrived with NO fix (absent body/coordinates — e.g. an older app build) is 409 &#x60;error.code &#x3D; GPS_REQUIRED&#x60; (fail closed; clients branch on the code and localize). Legacy address-only bookings (no pin) skip the check entirely. Admin bypasses the geofence (support acts on behalf, off-site). The accepted fix is persisted server-side as audit evidence; body &#x60;lat&#x60;/&#x60;lng&#x60; are both-or-neither (400 otherwise, like create-booking). Once arrived, start + check-in are NO LONGER proximity-gated. 
  ///
  /// Parameters:
  /// * [id] 
  /// * [startJobRequest] 
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [InlineObject] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<InlineObject>> arrivedBooking({ 
    required String id,
    StartJobRequest? startJobRequest,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/bookings/{id}/arrived'.replaceAll('{' r'id' '}', encodeQueryParameter(_serializers, id, const FullType(String)).toString());
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
      const _type = FullType(StartJobRequest);
      _bodyData = startJobRequest == null ? null : _serializers.serialize(startJobRequest, specifiedType: _type);

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

  /// Customer/admin cancels a pre-arrival booking
  /// Status → &#x60;cancelled&#x60;. Allowed only PRE-ARRIVAL (&#x60;requested&#x60;/&#x60;accepted&#x60;/&#x60;en_route&#x60;) — once a guard is on-site the job runs to completion review. Enqueues &#x60;pguard.events.booking.cancelled&#x60;. Customer (request owner) or admin only. Cancelling a PAID booking FULL-REFUNDS the customer via payment&#39;s cancellation-refund consumer.  **A reason is REQUIRED.** The body carries a stable &#x60;reason&#x60; code (&#x60;changed_plan&#x60; | &#x60;mistake&#x60; | &#x60;not_needed&#x60; | &#x60;other&#x60;) plus an optional &#x60;note&#x60; (≤ 500 characters). A missing reason — or one that is not a customer code — is 400 with &#x60;error.code &#x3D; CANCEL_REASON_REQUIRED&#x60;; &#x60;reason &#x3D; other&#x60; with a blank note is 400 with &#x60;error.code &#x3D; CANCEL_NOTE_REQUIRED&#x60;. Clients branch on &#x60;error.code&#x60; and localize it — never on the message. Reason + note are persisted on the booking (&#x60;cancellation_reason&#x60; / &#x60;cancellation_note&#x60;) and carried on the event. 
  ///
  /// Parameters:
  /// * [id] 
  /// * [cancelBookingRequest] 
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [InlineObject] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<InlineObject>> cancelBooking({ 
    required String id,
    required CancelBookingRequest cancelBookingRequest,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/bookings/{id}/cancel'.replaceAll('{' r'id' '}', encodeQueryParameter(_serializers, id, const FullType(String)).toString());
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
      const _type = FullType(CancelBookingRequest);
      _bodyData = _serializers.serialize(cancelBookingRequest, specifiedType: _type);

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

  /// Assigned guard requests completion
  /// Status &#x60;arrived → pending_completion&#x60; — the guard REQUESTS completion; the customer then reviews (see review-completion). No event yet. 409 if the job was not started. Assigned guard only. 
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
  Future<Response<InlineObject>> completeBooking({ 
    required String id,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/bookings/{id}/complete'.replaceAll('{' r'id' '}', encodeQueryParameter(_serializers, id, const FullType(String)).toString());
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

  /// Create a booking request (customer only)
  /// A customer creates a booking request (status &#x60;requested&#x60;). Role gating is enforced in the handler (403 for non-customers). No event is emitted for a bare request.  &#x60;scheduled_at&#x60; must be in the FUTURE — the server compares against its own clock (never the client&#39;s), so a past-or-now &#x60;scheduled_at&#x60; is 400 with &#x60;error.code &#x3D; SCHEDULED_IN_PAST&#x60; (C4). Clients branch on the code and localize. 
  ///
  /// Parameters:
  /// * [createBookingRequest] 
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [InlineObject] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<InlineObject>> createBooking({ 
    required CreateBookingRequest createBookingRequest,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/bookings';
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
      const _type = FullType(CreateBookingRequest);
      _bodyData = _serializers.serialize(createBookingRequest, specifiedType: _type);

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

  /// Assigned guard submits an hourly check-in (photo + GPS)
  /// The ASSIGNED guard checks in for &#x60;hour_number&#x60; of a job IN PROGRESS (status &#x60;arrived&#x60; with &#x60;work_started_at&#x60; stamped by start). &#x60;multipart/form-data&#x60; — server-mediated upload following the chat-attachment house pattern: the photo is validated (size before magic bytes; JPEG/PNG/WEBP ≤ 10MB), the SERVER uploads it to S3/MinIO under a server-generated key (clients never supply keys or see credentials), and only the key + metadata are persisted. Enqueues &#x60;pguard.events.booking.progress_reported&#x60; into the outbox in the SAME transaction.  Rules: &#x60;hour_number&#x60; must be within &#x60;1..&#x3D;hours&#x60;; hour N opens once N−1 hours have elapsed since &#x60;work_started_at&#x60; (409 &#x60;CONFLICT&#x60; too-early otherwise); the check-in window CLOSES 30min past the worked end (&#x60;work_started_at + hours&#x60;) — a later check-in is 409 &#x60;CHECK_IN_WINDOW_CLOSED&#x60; (G1; the 30-min grace keeps legitimate late back-filling of the final hour valid). One check-in per hour — a duplicate &#x60;hour_number&#x60; is 409 &#x60;DUPLICATE_CHECK_IN&#x60; (checked BEFORE the upload), so a client retry can never double-report and uploads nothing; clients branch on &#x60;error.code&#x60;, not the message. Strictly the assigned guard (no admin bypass — a report is the guard&#39;s first-person attestation of presence). GPS is optional (the guard may be offline at capture); when sent, &#x60;lat&#x60;+&#x60;lng&#x60; must come together.  &gt; **⚠️ Deployment dependency (tracked, NOT yet satisfied):** the booking service &gt; accepts bodies up to 12 MiB on this route, but the api-gateway currently buffers &gt; EVERY proxied body at a hard 1 MiB (&#x60;proxy.rs MAX_BODY_BYTES&#x60; → 413) and staging &gt; nginx caps at 2 MB (&#x60;client_max_body_size 2m&#x60;). Until the gateway grows a &gt; per-route body-cap carve-out (≥ 12 MiB for this route; in-flight gateway slice) &gt; + a location-scoped nginx override, photos over ~1 MiB get **413 at the edge** &gt; and never reach this endpoint. Mobile wiring MUST gate on that follow-up. 
  ///
  /// Parameters:
  /// * [id] 
  /// * [hourNumber] - Which job-hour this check-in covers (1-based, ≤ the booking's `hours`).
  /// * [photo] - The check-in photo (JPEG/PNG/WEBP, ≤ 10MB).
  /// * [lat] - GPS at capture time (optional; pair with `lng`).
  /// * [lng] - GPS at capture time (optional; pair with `lat`).
  /// * [accuracy] - GPS accuracy in meters (optional; non-finite/negative/absurd values are discarded server-side
  /// * [note] - Optional free-text note (trimmed; empty treated as absent; max 2000 characters).
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [CreateProgressReport200Response] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<CreateProgressReport200Response>> createProgressReport({ 
    required String id,
    required int hourNumber,
    required MultipartFile photo,
    double? lat,
    double? lng,
    double? accuracy,
    String? note,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/bookings/{id}/progress-reports'.replaceAll('{' r'id' '}', encodeQueryParameter(_serializers, id, const FullType(String)).toString());
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
            'name': 'bearerAuth',
          },
        ],
        ...?extra,
      },
      contentType: 'multipart/form-data',
      validateStatus: validateStatus,
    );

    dynamic _bodyData;

    try {
      _bodyData = FormData.fromMap(<String, dynamic>{
        r'hour_number': encodeFormParameter(_serializers, hourNumber, const FullType(int)),
        r'photo': photo,
        if (lat != null) r'lat': encodeFormParameter(_serializers, lat, const FullType(double)),
        if (lng != null) r'lng': encodeFormParameter(_serializers, lng, const FullType(double)),
        if (accuracy != null) r'accuracy': encodeFormParameter(_serializers, accuracy, const FullType(double)),
        if (note != null) r'note': encodeFormParameter(_serializers, note, const FullType(String)),
      });

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

    CreateProgressReport200Response? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(CreateProgressReport200Response),
      ) as CreateProgressReport200Response;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<CreateProgressReport200Response>(
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

  /// Assigned guard withdraws (after accepting, pre-arrival)
  /// The ASSIGNED guard backs out → status &#x60;declined&#x60; (terminal). v2 is first-come-accept, so there is no per-guard offer to decline before accepting — decline is the assigned guard withdrawing. Legal PRE-ARRIVAL only: &#x60;accepted → declined&#x60; AND &#x60;en_route → declined&#x60; (the guard already set off but has not reached the site). Once &#x60;arrived&#x60; the guard can no longer self-withdraw (409) — the job runs to completion review. Enqueues &#x60;pguard.events.booking.declined&#x60; in the same transaction. 403 if the caller is not the assigned guard.  **Money:** withdrawing from a PAID booking (&#x60;paid_at&#x60; set — the normal &#x60;en_route&#x60; case, since pre-pay gates &#x60;accepted → en_route&#x60;) FULL-REFUNDS the customer via payment&#39;s cancellation-refund consumer of &#x60;booking.declined&#x60;. The customer is never charged for a job the guard abandoned.  **A reason is REQUIRED.** The body carries a stable &#x60;reason&#x60; code (&#x60;emergency&#x60; | &#x60;sick&#x60; | &#x60;cannot_reach&#x60; | &#x60;other&#x60;) plus an optional &#x60;note&#x60; (≤ 500 characters). A missing reason — or one that is not a guard code — is 400 with &#x60;error.code &#x3D; CANCEL_REASON_REQUIRED&#x60;; &#x60;reason &#x3D; other&#x60; with a blank note is 400 with &#x60;error.code &#x3D; CANCEL_NOTE_REQUIRED&#x60;. Clients branch on &#x60;error.code&#x60; and localize it — never on the message. Reason + note are persisted on the booking (&#x60;cancellation_reason&#x60; / &#x60;cancellation_note&#x60;) and carried on the event. 
  ///
  /// Parameters:
  /// * [id] 
  /// * [declineBookingRequest] 
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [InlineObject] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<InlineObject>> declineBooking({ 
    required String id,
    required DeclineBookingRequest declineBookingRequest,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/bookings/{id}/decline'.replaceAll('{' r'id' '}', encodeQueryParameter(_serializers, id, const FullType(String)).toString());
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
      const _type = FullType(DeclineBookingRequest);
      _bodyData = _serializers.serialize(declineBookingRequest, specifiedType: _type);

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

  /// Assigned guard is en route
  /// Status → &#x60;en_route&#x60;. Enqueues &#x60;pguard.events.booking.guard_en_route&#x60; into the outbox in the same transaction. Assigned guard only. 
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
  Future<Response<InlineObject>> enRouteBooking({ 
    required String id,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/bookings/{id}/en-route'.replaceAll('{' r'id' '}', encodeQueryParameter(_serializers, id, const FullType(String)).toString());
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

  /// Get one booking the caller participates in
  /// 
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
  Future<Response<InlineObject>> getBooking({ 
    required String id,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/bookings/{id}'.replaceAll('{' r'id' '}', encodeQueryParameter(_serializers, id, const FullType(String)).toString());
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

  /// Discovery — ONLINE approved guards enriched with their rating summary
  /// booking owns discovery but none of the guard catalog (profile), reviews (rating), or live presence (presence). This lists the APPROVED guard catalog (read from profile&#39;s &#x60;/internal/guards&#x60; over a service-JWT), RESTRICTED to guards who are currently ONLINE — live per presence&#39;s &#x60;/internal/online-guards&#x60; (&#x60;is_online&#x60; AND a fresh GPS fix, \&quot;พร้อมรับงาน\&quot;) — and enriches each with the guard&#39;s live rating summary (read from rating&#39;s &#x60;/internal/guards/{id}/rating-summary&#x60;).  Online filter: an OFFLINE approved guard is dropped from the list. FAIL-OPEN on presence: if the presence consult errors/times out, the full approved list is returned UNFILTERED (a presence hiccup must never blank discovery and block all bookings).  Best-effort on ratings: a guard whose rating lookup fails still appears with &#x60;average_rating: null&#x60; and &#x60;review_count: 0&#x60;.  Nearest-first (C2): when the MEETUP point &#x60;lat&#x60;/&#x60;lng&#x60; is supplied, the surviving guards are sorted ASCENDING by the straight-line distance from each guard&#39;s LIVE position (per presence) to the meetup, and every entry carries &#x60;distance_m&#x60;. Omit the coordinates and the order is the catalog order with &#x60;distance_m&#x60; omitted (backward compatible). Guards with no known live position sort last. 
  ///
  /// Parameters:
  /// * [scheduledAt] - Start of the customer's chosen window. When supplied WITH `hours`, the busy-guard exclusion is scoped to this window (a guard booked for a non-overlapping time is still offered). Omit both for the coarse \"any active job\" exclusion. 
  /// * [hours] - Length of the window in hours (paired with `scheduled_at`).
  /// * [lat] - Meetup latitude (the booking's site pin). Both-or-neither with `lng`; when present the list is sorted nearest-to-meetup and each entry carries `distance_m`. 
  /// * [lng] - Meetup longitude (paired with `lat`).
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [ListAvailableGuards200Response] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<ListAvailableGuards200Response>> listAvailableGuards({ 
    DateTime? scheduledAt,
    int? hours,
    double? lat,
    double? lng,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/available-guards';
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
      if (scheduledAt != null) r'scheduled_at': encodeQueryParameter(_serializers, scheduledAt, const FullType(DateTime)),
      if (hours != null) r'hours': encodeQueryParameter(_serializers, hours, const FullType(int)),
      if (lat != null) r'lat': encodeQueryParameter(_serializers, lat, const FullType(double)),
      if (lng != null) r'lng': encodeQueryParameter(_serializers, lng, const FullType(double)),
    };

    final _response = await _dio.request<Object>(
      _path,
      options: _options,
      queryParameters: _queryParameters,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );

    ListAvailableGuards200Response? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(ListAvailableGuards200Response),
      ) as ListAvailableGuards200Response;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<ListAvailableGuards200Response>(
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

  /// List the caller&#39;s bookings
  /// Bookings where the caller is the customer OR the assigned guard, newest first.
  ///
  /// Parameters:
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [ListBookings200Response] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<ListBookings200Response>> listBookings({ 
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/bookings';
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

    ListBookings200Response? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(ListBookings200Response),
      ) as ListBookings200Response;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<ListBookings200Response>(
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

  /// Open-job discovery — requested bookings with no guard yet (guard only)
  /// Bookings a guard can claim: &#x60;status &#x3D; requested AND guard_id IS NULL&#x60;. Guard/admin only (403 otherwise). A literal path segment registered beside &#x60;/bookings/{id}&#x60; — static segments win in the router (same precedent as calling&#39;s &#x60;/calls/ice&#x60;), and the gateway&#39;s existing &#x60;/bookings&#x60; prefix rule routes it with no gateway change.  DIRECTED OFFER (C3): a booking directed at one guard (&#x60;target_guard_id&#x60; set) appears here ONLY for that guard — every other guard sees just OPEN bookings (&#x60;target_guard_id&#x60; null). So the returned set is &#x60;target_guard_id IS NULL OR target_guard_id &#x3D; &lt;caller&gt;&#x60;.  Filtering: with &#x60;lat&#x60;+&#x60;lng&#x60; (and optional &#x60;radius_km&#x60;, default 10) only bookings that HAVE coordinates within the radius are returned, nearest first. Without coordinates, all open bookings are returned newest-first (coordinates on bookings are optional). &#x60;lat&#x60;/&#x60;lng&#x60; must be sent together; &#x60;radius_km&#x60; requires them. Paginated with &#x60;limit&#x60;/&#x60;offset&#x60;. 
  ///
  /// Parameters:
  /// * [lat] - Guard's latitude (must be paired with `lng`).
  /// * [lng] - Guard's longitude (must be paired with `lat`).
  /// * [radiusKm] - Great-circle search radius in km (requires `lat`+`lng`).
  /// * [limit] - Page size (max 200).
  /// * [offset] - Rows to skip.
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [ListBookings200Response] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<ListBookings200Response>> listOpenBookings({ 
    double? lat,
    double? lng,
    double? radiusKm = 10,
    int? limit = 50,
    int? offset = 0,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/bookings/open';
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
      if (lat != null) r'lat': encodeQueryParameter(_serializers, lat, const FullType(double)),
      if (lng != null) r'lng': encodeQueryParameter(_serializers, lng, const FullType(double)),
      if (radiusKm != null) r'radius_km': encodeQueryParameter(_serializers, radiusKm, const FullType(double)),
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

    ListBookings200Response? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(ListBookings200Response),
      ) as ListBookings200Response;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<ListBookings200Response>(
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

  /// List a booking&#39;s check-in reports (participants only)
  /// The booking&#39;s customer (owner) and assigned guard may read (admin bypasses) — IDOR-gated both ways; a non-participant gets 403. Reports are returned in &#x60;hour_number&#x60; order, each with a FRESHLY presigned photo URL (the stored key is re-signed on every read — signed URLs are never persisted as the source of truth). 
  ///
  /// Parameters:
  /// * [id] 
  /// * [limit] - Page size (max 200).
  /// * [offset] - Rows to skip.
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [ListProgressReports200Response] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<ListProgressReports200Response>> listProgressReports({ 
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
    final _path = r'/bookings/{id}/progress-reports'.replaceAll('{' r'id' '}', encodeQueryParameter(_serializers, id, const FullType(String)).toString());
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

    ListProgressReports200Response? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(ListProgressReports200Response),
      ) as ListProgressReports200Response;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<ListProgressReports200Response>(
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

  /// List ACTIVE catalog services (customer-facing picker)
  /// The customer-facing service picker: the ACTIVE catalog services a customer can book against, projected to a narrow shape (&#x60;id&#x60;, &#x60;name_th&#x60;, &#x60;name_en&#x60;, &#x60;base_fee&#x60;, &#x60;min_hours&#x60;) — &#x60;notes&#x60;/&#x60;is_active&#x60;/timestamps are admin-only and NOT exposed here. Any authenticated user may read it (NOT admin-gated, unlike &#x60;/admin/pricing/services&#x60;). A customer passes the chosen &#x60;id&#x60; as &#x60;CreateBookingRequest.service_id&#x60;, which resolves the booking&#39;s server-owned &#x60;base_fee&#x60; and &#x60;min_hours&#x60; floor on the charge path. 
  ///
  /// Parameters:
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [ListServices200Response] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<ListServices200Response>> listServices({ 
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/services';
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

    ListServices200Response? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(ListServices200Response),
      ) as ListServices200Response;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<ListServices200Response>(
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

  /// Customer reviews the guard&#39;s completion request
  /// The CUSTOMER (request owner) decides: &#x60;approve&#x60; → &#x60;completed&#x60; (emits &#x60;pguard.events.booking.completed&#x60; with &#x60;booked_hours&#x60; + &#x60;actual_seconds&#x60;, driving payment proration) or &#x60;reject&#x60; → back to &#x60;arrived&#x60; (the guard finishes). Customer/admin only; the booking must be &#x60;pending_completion&#x60;. 
  ///
  /// Parameters:
  /// * [id] 
  /// * [reviewCompletionRequest] 
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [InlineObject] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<InlineObject>> reviewCompletion({ 
    required String id,
    required ReviewCompletionRequest reviewCompletionRequest,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/bookings/{id}/review-completion'.replaceAll('{' r'id' '}', encodeQueryParameter(_serializers, id, const FullType(String)).toString());
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
      const _type = FullType(ReviewCompletionRequest);
      _bodyData = _serializers.serialize(reviewCompletionRequest, specifiedType: _type);

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

  /// Guard passes on an open offer (server-tracked skip)
  /// The guard SKIPS an open offer they aren&#39;t taking. Server-tracked (per-guard) so open-job discovery (&#x60;GET /bookings/open&#x60;) stops re-offering THIS booking to THIS guard — the booking stays &#x60;requested&#x60;/open for OTHER guards (NOT a cancellation). Idempotent. Guard only. 
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
  /// Returns a [Future] containing a [Response] with a [SkipBooking200Response] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<SkipBooking200Response>> skipBooking({ 
    required String id,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/bookings/{id}/skip'.replaceAll('{' r'id' '}', encodeQueryParameter(_serializers, id, const FullType(String)).toString());
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

    SkipBooking200Response? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(SkipBooking200Response),
      ) as SkipBooking200Response;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<SkipBooking200Response>(
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

  /// Assigned guard starts the job (start-time gate only — no geofence)
  /// Stamps &#x60;work_started_at&#x60; (the proration basis); status stays &#x60;arrived&#x60; (no event). Assigned guard only; the booking must be &#x60;arrived&#x60;. A second start is an idempotent no-op (the time gate is not re-run on the retry of an already-started job). The job must be started before completion can be requested.  **Start-time gate (G3):** the start window opens at &#x60;scheduled_at − 15min&#x60; (an early grace for a guard who is on-site a touch ahead of schedule). A start before that is 409 with &#x60;error.code &#x3D; START_TOO_EARLY&#x60; (there is no upper bound — a late start is legitimate). Admin starts bypass the gate (support acts on behalf).  **No geofence (G4):** proximity is now proven at ARRIVAL (see PUT &#x60;/bookings/{id}/arrived&#x60;, the 120m fence), so start is NO LONGER proximity-gated — a start never returns &#x60;NOT_AT_SITE&#x60;/&#x60;GPS_REQUIRED&#x60;. The OPTIONAL body still carries the guard&#39;s GPS fix, which is persisted server-side as audit evidence of where the job was started; body &#x60;lat&#x60;/&#x60;lng&#x60; are both-or-neither (400 otherwise, like create-booking). 
  ///
  /// Parameters:
  /// * [id] 
  /// * [startJobRequest] 
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [InlineObject] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<InlineObject>> startBooking({ 
    required String id,
    StartJobRequest? startJobRequest,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/bookings/{id}/start'.replaceAll('{' r'id' '}', encodeQueryParameter(_serializers, id, const FullType(String)).toString());
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
      const _type = FullType(StartJobRequest);
      _bodyData = startJobRequest == null ? null : _serializers.serialize(startJobRequest, specifiedType: _type);

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
