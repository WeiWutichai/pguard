//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

import 'dart:async';

import 'package:built_value/json_object.dart';
import 'package:built_value/serializer.dart';
import 'package:dio/dio.dart';

import 'package:pguard_profile_api/src/api_util.dart';
import 'package:pguard_profile_api/src/model/error_body.dart';
import 'package:pguard_profile_api/src/model/get_my_profile200_response.dart';
import 'package:pguard_profile_api/src/model/get_public_guard_profile200_response.dart';
import 'package:pguard_profile_api/src/model/inline_object.dart';
import 'package:pguard_profile_api/src/model/inline_object1.dart';
import 'package:pguard_profile_api/src/model/upsert_customer_profile_request.dart';
import 'package:pguard_profile_api/src/model/upsert_guard_profile_request.dart';

class ProfileApi {

  final Dio _dio;

  final Serializers _serializers;

  const ProfileApi(this._dio, this._serializers);

  /// The caller&#39;s own profile (account number MASKED)
  /// Returns the caller&#39;s profile, tagged by &#x60;kind&#x60; (&#x60;guard&#x60; or &#x60;customer&#x60;) so the client need not guess. For a guard the &#x60;account_number&#x60; is MASKED to its last 4 characters (PDPA §7). A caller with no profile (or an admin, who has no self-profile in this slice) receives 404. 
  ///
  /// Parameters:
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [GetMyProfile200Response] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<GetMyProfile200Response>> getMyProfile({ 
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/profile/me';
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

    GetMyProfile200Response? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(GetMyProfile200Response),
      ) as GetMyProfile200Response;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<GetMyProfile200Response>(
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

  /// Assigned guard&#39;s public mini-profile (customer live-tracking map)
  /// The MINI-profile (name + years of experience) of the guard assigned to the caller&#39;s booking, for the customer live-tracking map. **IDOR-gated:** a &#x60;customer&#x60; may read it ONLY while they have an ACTIVE booking with this guard (an event-derived read-model projected from &#x60;pguard.events.booking.*&#x60;); a &#x60;guard&#x60; may read only their own; an &#x60;admin&#x60; may read any. A customer without an active booking gets **403** (NOT 404 — no existence probe). **Approval-gated:** an un-approved or unknown guard returns **404** (its existence is never revealed). Returns ONLY &#x60;{ user_id, full_name, years_of_experience }&#x60; — never the bank/address/DOB/emergency-contact PII. &#x60;full_name&#x60; is PII reachable by a non-owner ONLY under this active-booking trust boundary (PDPA §7); a photo is deferred (no avatar storage). 
  ///
  /// Parameters:
  /// * [id] - The assigned guard's user_id.
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [GetPublicGuardProfile200Response] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<GetPublicGuardProfile200Response>> getPublicGuardProfile({ 
    required String id,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/guards/{id}/public'.replaceAll('{' r'id' '}', encodeQueryParameter(_serializers, id, const FullType(String)).toString());
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

    GetPublicGuardProfile200Response? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(GetPublicGuardProfile200Response),
      ) as GetPublicGuardProfile200Response;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<GetPublicGuardProfile200Response>(
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

  /// Update the caller&#39;s EXISTING guard profile (role&#x3D;guard)
  /// Updates an existing guard profile&#39;s editable fields. Unlike &#x60;POST&#x60; this never inserts: a caller with no profile yet receives 404. Requires role &#x60;guard&#x60;. The read-back masks &#x60;account_number&#x60; (PDPA). 
  ///
  /// Parameters:
  /// * [upsertGuardProfileRequest] 
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [InlineObject] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<InlineObject>> updateGuardProfile({ 
    required UpsertGuardProfileRequest upsertGuardProfileRequest,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/profile/guard';
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
      const _type = FullType(UpsertGuardProfileRequest);
      _bodyData = _serializers.serialize(upsertGuardProfileRequest, specifiedType: _type);

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

  /// Create or update the caller&#39;s customer profile (profile_token OR logged-in customer)
  /// Upserts the caller&#39;s customer profile (minimal in this slice: full name + address). **Dual auth** (either satisfies the request):   - a single-use &#x60;profileToken&#x60; (&#x60;customer_profile&#x60;) from registration (the user is     not logged in yet); consumed single-use, and a &#x60;guard_profile&#x60; token is rejected     here (purpose isolation).   - a logged-in customer&#39;s &#x60;bearerAuth&#x60; access token (a later self-edit), role-gated.  Writes ONLY the customer profile schema; identity&#39;s approval state is never written directly. The FIRST creation additionally emits &#x60;user.approved&#x60; (transactional outbox): **customers are auto-approved on their first profile submission** — there is no human review step for hirers (guards keep the admin approve/reject flow). The fields in this minimal slice are optional, so \&quot;submission\&quot; — not field completeness — is the gate (the official client makes &#x60;address&#x60; required). identity consumes the event and flips its own &#x60;approval_status&#x60;, so the account becomes loginable moments after this call returns. A later self-edit re-upsert emits nothing. 
  ///
  /// Parameters:
  /// * [upsertCustomerProfileRequest] 
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [InlineObject1] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<InlineObject1>> upsertCustomerProfile({ 
    required UpsertCustomerProfileRequest upsertCustomerProfileRequest,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/profile/customer';
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
            'name': 'profileToken',
          },{
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
      const _type = FullType(UpsertCustomerProfileRequest);
      _bodyData = _serializers.serialize(upsertCustomerProfileRequest, specifiedType: _type);

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

  /// Create or update the caller&#39;s guard profile (profile_token OR logged-in guard)
  /// Upserts the caller&#39;s guard profile. **Dual auth** (either satisfies the request):   - a single-use, purpose-scoped &#x60;profileToken&#x60; (&#x60;guard_profile&#x60;) from registration     (&#x60;POST /auth/register&#x60;) — the user is NOT logged in yet. The token is consumed     single-use; a &#x60;customer_profile&#x60; token is rejected here (purpose isolation).   - a logged-in guard&#39;s &#x60;bearerAuth&#x60; access token (a later self-edit), role-gated.  Writes ONLY the profile schema: on first create &#x60;approval_status&#x60; is &#x60;pending&#x60;; a later upsert edits fields but NEVER changes the approval decision (only an admin does, via approve/reject), and &#x60;users.role&#x60; (identity-owned) is never touched. The read-back masks &#x60;account_number&#x60; (PDPA). 
  ///
  /// Parameters:
  /// * [upsertGuardProfileRequest] 
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [InlineObject] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<InlineObject>> upsertGuardProfile({ 
    required UpsertGuardProfileRequest upsertGuardProfileRequest,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/profile/guard';
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
            'name': 'profileToken',
          },{
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
      const _type = FullType(UpsertGuardProfileRequest);
      _bodyData = _serializers.serialize(upsertGuardProfileRequest, specifiedType: _type);

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
