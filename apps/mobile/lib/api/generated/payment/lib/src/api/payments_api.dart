//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

import 'dart:async';

import 'package:built_value/json_object.dart';
import 'package:built_value/serializer.dart';
import 'package:dio/dio.dart';

import 'package:pguard_payment_api/src/api_util.dart';
import 'package:pguard_payment_api/src/model/create_payment_request.dart';
import 'package:pguard_payment_api/src/model/error_body.dart';
import 'package:pguard_payment_api/src/model/get_prompt_pay200_response.dart';
import 'package:pguard_payment_api/src/model/list_guard_earnings200_response.dart';
import 'package:pguard_payment_api/src/model/list_payments200_response.dart';
import 'package:pguard_payment_api/src/model/pay_with_slip200_response.dart';

class PaymentsApi {

  final Dio _dio;

  final Serializers _serializers;

  const PaymentsApi(this._dio, this._serializers);

  /// PRE-PAY a booking&#39;s estimate (createPayment)
  /// After a guard ACCEPTS, the customer pays the ESTIMATE up front. The client sends ONLY the &#x60;booking_id&#x60;; the amount is computed SERVER-SIDE from the authoritative booking (&#x60;base_fee × hours × guard_count + tip&#x60;, read via the service-JWT&#39;d internal booking read) — the client NEVER sends the amount. Authz: the caller must be the booking&#39;s customer and the booking must be in a payable state (post-accept, pre-complete) → else 403/409.  This payment GATES the booking&#39;s en_route (booking consumes &#x60;payment.completed&#x60; → sets &#x60;paid_at&#x60;). Idempotent per booking: a repeat returns the existing payment (200), never a second charge. 
  ///
  /// Parameters:
  /// * [createPaymentRequest] 
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [PayWithSlip200Response] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<PayWithSlip200Response>> createPayment({ 
    required CreatePaymentRequest createPaymentRequest,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/payments';
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
      const _type = FullType(CreatePaymentRequest);
      _bodyData = _serializers.serialize(createPaymentRequest, specifiedType: _type);

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

    PayWithSlip200Response? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(PayWithSlip200Response),
      ) as PayWithSlip200Response;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<PayWithSlip200Response>(
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

  /// Get one payment the caller owns (or admin)
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
  /// Returns a [Future] containing a [Response] with a [PayWithSlip200Response] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<PayWithSlip200Response>> getPayment({ 
    required String id,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/payments/{id}'.replaceAll('{' r'id' '}', encodeQueryParameter(_serializers, id, const FullType(String)).toString());
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

    PayWithSlip200Response? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(PayWithSlip200Response),
      ) as PayWithSlip200Response;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<PayWithSlip200Response>(
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

  /// PromptPay transfer instructions for a booking (where to pay)
  /// Tells the customer WHERE and HOW MUCH to transfer so they can pay the booking by PromptPay and then settle via &#x60;POST /payments/{id}/slip&#x60;. &#x60;{id}&#x60; is the BOOKING id. Own-only (the booking&#39;s customer) → else 403; the booking must be in a payable state (post-accept, pre-complete) → else 409.  Returns the **server-computed estimate** (&#x60;base_fee × hours × guard_count + tip&#x60; — the SAME amount the slip/pre-pay handlers charge; the client never computes it), our **receiving account** formatted for display, and the authoritative **EMVCo PromptPay &#x60;qr_payload&#x60;**.  The &#x60;qr_payload&#x60; is generated **server-side, in ONE authoritative place**, from &#x60;RECEIVING_ACCOUNT&#x60; + the estimate — a standard PromptPay/EMVCo merchant-presented QR (Payload-Format &#x60;00&#x60;, Point-of-Initiation &#x60;01&#x60;, Merchant-Account &#x60;29&#x60; with the PromptPay AID &#x60;A000000677010111&#x60; + the proxy phone/national-id from &#x60;RECEIVING_ACCOUNT&#x60;, amount tag &#x60;54&#x60;, currency &#x60;53&#x60;&#x3D;764 THB, country &#x60;58&#x60;&#x3D;TH, CRC &#x60;63&#x60;). The mobile renders it as a QR and MUST NOT rebuild its own — so the amount + receiver can never drift from the server.  **Only valid under &#x60;PAYMENT_PROVIDER&#x3D;slip2go&#x60;.** Under the simulated default this returns 409 &#x60;SLIP_DISABLED&#x60; (there is nowhere to transfer — the client uses &#x60;POST /payments&#x60;). &#x60;RECEIVING_ACCOUNT&#x60; must be a PromptPay-addressable id (a mobile phone or a national/tax id); a plain bank account number cannot be encoded as a PromptPay QR (→ server config error).  No DB write and no Slip2Go call — purely informational. 
  ///
  /// Parameters:
  /// * [id] - The booking id to pay.
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [GetPromptPay200Response] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<GetPromptPay200Response>> getPromptPay({ 
    required String id,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/payments/{id}/promptpay'.replaceAll('{' r'id' '}', encodeQueryParameter(_serializers, id, const FullType(String)).toString());
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

    GetPromptPay200Response? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(GetPromptPay200Response),
      ) as GetPromptPay200Response;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<GetPromptPay200Response>(
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

  /// The assigned guard&#39;s earning basis (role&#x3D;guard)
  /// The caller&#39;s COMPLETED (paid) jobs, newest first, each with the clamped &#x60;actual_hours&#x60; ACTUALLY worked (persisted at reconcile; &#x60;null&#x60; for an even-match / not-yet-reconciled row). GUARD-ONLY (keyed on the JWT &#x60;sub&#x60; → the assigned guard). The guard app pairs each &#x60;booking_id&#x60; with the &#x60;base_fee&#x60; from its own booking feed and pays &#x60;base_fee × actual_hours&#x60; (falling back to the booked hours when &#x60;actual_hours&#x60; is null), so a job that finished early — and was overpay-refunded to the customer — pays the guard for the hours actually worked rather than the full booked estimate. Cancelled/withdrawn (refunded) jobs are excluded (the guard earned nothing there). 
  ///
  /// Parameters:
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [ListGuardEarnings200Response] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<ListGuardEarnings200Response>> listGuardEarnings({ 
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/payments/earnings';
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

    ListGuardEarnings200Response? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(ListGuardEarnings200Response),
      ) as ListGuardEarnings200Response;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<ListGuardEarnings200Response>(
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

  /// List the caller&#39;s payments
  /// Payments where the caller is the paying customer, newest first. v2 is POST-PAY: there is no customer-initiated charge endpoint — the bill is RAISED on completion by the &#x60;booking.completed&#x60; consumer (base prorated to the hours actually worked + the flat tip) and emitted as &#x60;pguard.events.payment.completed&#x60;. This list is how the customer sees what was billed. 
  ///
  /// Parameters:
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [ListPayments200Response] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<ListPayments200Response>> listPayments({ 
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/payments';
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

    ListPayments200Response? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(ListPayments200Response),
      ) as ListPayments200Response;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<ListPayments200Response>(
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

  /// Pay a booking with a Slip2Go-verified transfer slip (REAL money path)
  /// THE MONEY PATH (real). &#x60;{id}&#x60; is the BOOKING id. The customer transfers to OUR PromptPay/bank account, then uploads the transfer SLIP image here. The payment service verifies the slip with **Slip2Go** (&#x60;POST /verify-slip/qr-image/info&#x60;) — confirming it is genuine, paid to OUR account (&#x60;checkReceiver&#x60;), and for at least the server-computed estimate (&#x60;checkAmount: gte&#x60;) — then RE-VALIDATES on our side (amount ≥ estimate, receiver &#x3D;&#x3D; our account) and stamps the payment paid (&#x60;payment_method&#x3D;promptpay_slip&#x60;), emitting the SAME &#x60;payment.completed&#x60; event that gates en_route (no new event).  Available only when the service runs with &#x60;PAYMENT_PROVIDER&#x3D;slip2go&#x60;; under the simulated default this returns 409 &#x60;SLIP_DISABLED&#x60;. Own-only (the booking&#39;s customer) → else 403.  **Anti-fraud / dedupe guarantee:** a verified slip&#39;s &#x60;transRef&#x60; and Slip2Go &#x60;referenceId&#x60; are stored under a UNIQUE constraint, so ONE slip can NEVER pay two bookings (a reused slip → 409 &#x60;SLIP_DUPLICATE&#x60;). **Idempotent:** re-submitting the SAME accepted slip returns the existing payment (200), no double-charge.  Failure modes carry a machine-readable &#x60;error.code&#x60; (branch on it, not the message): &#x60;SLIP_VERIFY_FAILED&#x60; (Slip2Go rejected it), &#x60;SLIP_AMOUNT_TOO_LOW&#x60; (underpay), &#x60;SLIP_WRONG_RECEIVER&#x60; (paid to another account), &#x60;SLIP_DUPLICATE&#x60; (already used), &#x60;SLIP_DISABLED&#x60; (provider not slip2go). 
  ///
  /// Parameters:
  /// * [id] - The booking id to settle.
  /// * [file] - The transfer-slip image (JPEG/PNG/WEBP, ≤ 10 MB).
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [PayWithSlip200Response] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<PayWithSlip200Response>> payWithSlip({ 
    required String id,
    required MultipartFile file,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/payments/{id}/slip'.replaceAll('{' r'id' '}', encodeQueryParameter(_serializers, id, const FullType(String)).toString());
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
        r'file': file,
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

    PayWithSlip200Response? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(PayWithSlip200Response),
      ) as PayWithSlip200Response;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<PayWithSlip200Response>(
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
