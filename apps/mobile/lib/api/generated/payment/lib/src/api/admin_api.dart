//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

import 'dart:async';

import 'package:built_value/json_object.dart';
import 'package:built_value/serializer.dart';
import 'package:dio/dio.dart';

import 'package:pguard_payment_api/src/api_util.dart';
import 'package:pguard_payment_api/src/model/admin_customer_spend_report200_response.dart';
import 'package:pguard_payment_api/src/model/admin_refund_queue200_response.dart';
import 'package:pguard_payment_api/src/model/admin_revenue_report200_response.dart';
import 'package:pguard_payment_api/src/model/date.dart';
import 'package:pguard_payment_api/src/model/error_body.dart';
import 'package:pguard_payment_api/src/model/export_deduction_request.dart';
import 'package:pguard_payment_api/src/model/export_payout_request.dart';
import 'package:pguard_payment_api/src/model/export_refund_request.dart';
import 'package:pguard_payment_api/src/model/get_deduction_batch200_response.dart';
import 'package:pguard_payment_api/src/model/get_payout_batch200_response.dart';
import 'package:pguard_payment_api/src/model/get_payout_config200_response.dart';
import 'package:pguard_payment_api/src/model/get_refund_batch200_response.dart';
import 'package:pguard_payment_api/src/model/internal_export_user200_response.dart';
import 'package:pguard_payment_api/src/model/list_deduction_batches200_response.dart';
import 'package:pguard_payment_api/src/model/list_payments200_response.dart';
import 'package:pguard_payment_api/src/model/list_payout_batches200_response.dart';
import 'package:pguard_payment_api/src/model/list_refund_batches200_response.dart';
import 'package:pguard_payment_api/src/model/payment_status.dart';
import 'package:pguard_payment_api/src/model/preview_deductions200_response.dart';
import 'package:pguard_payment_api/src/model/preview_payout200_response.dart';
import 'package:pguard_payment_api/src/model/preview_refunds200_response.dart';
import 'package:pguard_payment_api/src/model/refund_status.dart';
import 'package:pguard_payment_api/src/model/set_deduction_batch_status200_response.dart';
import 'package:pguard_payment_api/src/model/set_deduction_batch_status_request.dart';
import 'package:pguard_payment_api/src/model/set_payout_batch_status200_response.dart';
import 'package:pguard_payment_api/src/model/set_payout_batch_status_request.dart';
import 'package:pguard_payment_api/src/model/set_refund_batch_status200_response.dart';
import 'package:pguard_payment_api/src/model/set_refund_batch_status_request.dart';
import 'package:pguard_payment_api/src/model/update_payout_config_request.dart';
import 'package:pguard_payment_api/src/model/vat_register_report200_response.dart';
import 'package:pguard_payment_api/src/model/void_deduction_batch_items_request.dart';
import 'package:pguard_payment_api/src/model/void_deduction_batch_request.dart';
import 'package:pguard_payment_api/src/model/void_payout_batch_items_request.dart';
import 'package:pguard_payment_api/src/model/void_payout_batch_request.dart';
import 'package:pguard_payment_api/src/model/void_refund_batch_items_request.dart';
import 'package:pguard_payment_api/src/model/void_refund_batch_request.dart';
import 'package:pguard_payment_api/src/model/wht_payee_report200_response.dart';

class AdminApi {

  final Dio _dio;

  final Serializers _serializers;

  const AdminApi(this._dio, this._serializers);

  /// Per-customer lifetime-spend report (role&#x3D;admin)
  /// Per-customer lifetime spend — for each customer, the summed effective amount of their actually-charged (&#x60;completed&#x60;) payments (prorated &#x60;final_amount&#x60; when set, else &#x60;amount&#x60;). Powers the web-admin customers page&#39;s spend column. Customers with no completed payment are omitted. Admin only (else 403). 
  ///
  /// Parameters:
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [AdminCustomerSpendReport200Response] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<AdminCustomerSpendReport200Response>> adminCustomerSpendReport({ 
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/admin/reports/customer-spend';
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

    AdminCustomerSpendReport200Response? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(AdminCustomerSpendReport200Response),
      ) as AdminCustomerSpendReport200Response;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<AdminCustomerSpendReport200Response>(
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

  /// List ALL payments cross-user (role&#x3D;admin, read-only ledger)
  /// The admin payment ledger — every payment (NOT owner-scoped, unlike &#x60;GET /payments&#x60;), newest first, with optional &#x60;status&#x60; and &#x60;customer_id&#x60; filters + limit/offset. Admin only (else 403). READ ONLY because refunds LEAVE AS A BATCH, not because they are automatic: they are sent through &#x60;POST /admin/refunds/export&#x60; (one SCB upload file), which is also the only thing that advances a refund to &#x60;processed&#x60;. There is deliberately no per-row refund action on this ledger. 
  ///
  /// Parameters:
  /// * [status] - Filter by payment status. An unrecognized value returns 400.
  /// * [customerId] - Restrict to payments placed by this customer (the customer's spend history).
  /// * [limit] 
  /// * [offset] 
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [ListPayments200Response] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<ListPayments200Response>> adminListPayments({ 
    PaymentStatus? status,
    String? customerId,
    int? limit = 50,
    int? offset = 0,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/admin/payments';
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
      if (status != null) r'status': encodeQueryParameter(_serializers, status, const FullType(PaymentStatus)),
      if (customerId != null) r'customer_id': encodeQueryParameter(_serializers, customerId, const FullType(String)),
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

  /// Refund queue — refunds awaiting action / in-progress (role&#x3D;admin)
  /// The admin refund queue — payments whose completion SETTLE left a refund owed (&#x60;refund_status&#x60; is set), newest first. Feeds the dashboard \&quot;แจ้งเตือน / คิวคืนเงิน\&quot; card. Optional &#x60;status&#x60; filter (&#x60;pending&#x60; &#x3D; awaiting action, &#x60;processed&#x60; &#x3D; done; omitted → both) + limit/offset. Returns the page of refund rows PLUS the total &#x60;count&#x60; matching the same filter (the badge count, independent of the page window). Admin only (else 403).  READ ONLY, and LANE A only (&#x60;payment.payments&#x60;). The money actually leaves through &#x60;POST /admin/refunds/export&#x60;, which covers both lanes — the other being the duplicate-transfer &#x60;payment.payment_slips&#x60; row, which this queue has never listed. A settle only ever sets &#x60;refund_status&#x3D;&#39;pending&#39;&#x60;; the export is what advances it to &#x60;&#39;processed&#39;&#x60;. 
  ///
  /// Parameters:
  /// * [status] - Filter by refund-workflow state. An unrecognized value returns 400.
  /// * [limit] 
  /// * [offset] 
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [AdminRefundQueue200Response] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<AdminRefundQueue200Response>> adminRefundQueue({ 
    RefundStatus? status,
    int? limit = 50,
    int? offset = 0,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/admin/refunds/queue';
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
      if (status != null) r'status': encodeQueryParameter(_serializers, status, const FullType(RefundStatus)),
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

    AdminRefundQueue200Response? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(AdminRefundQueue200Response),
      ) as AdminRefundQueue200Response;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<AdminRefundQueue200Response>(
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

  /// Revenue-trend analytics (role&#x3D;admin)
  /// Daily NET revenue (completed charges&#39; effective amount minus refunds) over &#x60;[from, to)&#x60;, plus a month-over-month comparison against the immediately-preceding equal-length window. Defaults to the last 30 days; the window is capped at 366 days. Admin only (else 403). 
  ///
  /// Parameters:
  /// * [from] - Inclusive window start (RFC3339). Default = `to − 30 days`.
  /// * [to] - Exclusive window end (RFC3339). Default = now.
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [AdminRevenueReport200Response] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<AdminRevenueReport200Response>> adminRevenueReport({ 
    DateTime? from,
    DateTime? to,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/admin/reports/revenue';
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
      if (from != null) r'from': encodeQueryParameter(_serializers, from, const FullType(DateTime)),
      if (to != null) r'to': encodeQueryParameter(_serializers, to, const FullType(DateTime)),
    };

    final _response = await _dio.request<Object>(
      _path,
      options: _options,
      queryParameters: _queryParameters,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );

    AdminRevenueReport200Response? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(AdminRevenueReport200Response),
      ) as AdminRevenueReport200Response;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<AdminRevenueReport200Response>(
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

  /// Re-download a generated sweep file (role&#x3D;admin)
  /// The STORED file text, byte for byte, with the same content type and filename the export served. Never regenerated — the backlog has moved on since, so a regenerated file would differ under the same batch reference. 404 when the batch is unknown or has no stored text. Admin only. 
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
  /// Returns a [Future] containing a [Response] with a [String] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<String>> downloadDeductionBatchFile({ 
    required String id,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/admin/deductions/batches/{id}/file'.replaceAll('{' r'id' '}', encodeQueryParameter(_serializers, id, const FullType(String)).toString());
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

    String? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : rawResponse as String;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<String>(
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

  /// Re-download a generated payout file (role&#x3D;admin)
  /// The STORED file text, byte for byte, with the same &#x60;text/plain; charset&#x3D;utf-8&#x60; content type and &#x60;SCB_file_reference_&lt;first 12 chars of the file ref&gt;.txt&#x60; filename the export served.  This is the escape hatch from the one-way door: the export marks the bookings paid and then streams the file ONCE, so a failed download / closed tab / proxy timeout used to leave those jobs paid forever with no copy of the file meant to pay them. The text is never REGENERATED — a regenerated file could differ (config, WHT rate or a guard profile changed) under the same batch ref. 404 both for an unknown batch and for one generated before the text was stored. Admin only. 
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
  /// Returns a [Future] containing a [Response] with a [String] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<String>> downloadPayoutBatchFile({ 
    required String id,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/admin/payouts/batches/{id}/file'.replaceAll('{' r'id' '}', encodeQueryParameter(_serializers, id, const FullType(String)).toString());
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

    String? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : rawResponse as String;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<String>(
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

  /// Re-download a generated refund file (role&#x3D;admin)
  /// The STORED file text, byte for byte, with the same &#x60;text/plain; charset&#x3D;utf-8&#x60; content type and &#x60;SCB_file_reference_&lt;first 12 chars of the file ref&gt;.txt&#x60; filename the export served.  This is the escape hatch from the one-way door: the export marks the obligations processed and then streams the file ONCE, so without a stored copy a failed download / closed tab / proxy timeout would leave those customers marked refunded with no file to actually refund them. The text is never REGENERATED — the backlog has moved on, so a regenerated file would differ under the same batch ref. 404 for an unknown batch or one with no stored text. Admin only. 
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
  /// Returns a [Future] containing a [Response] with a [String] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<String>> downloadRefundBatchFile({ 
    required String id,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/admin/refunds/batches/{id}/file'.replaceAll('{' r'id' '}', encodeQueryParameter(_serializers, id, const FullType(String)).toString());
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

    String? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : rawResponse as String;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<String>(
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

  /// Generate + download the SCB platform-cut sweep file (role&#x3D;admin)
  /// Build ONE SCB Business Net upload file (product **&#x60;OAT&#x60;**, own-account transfer) that sweeps the platform&#39;s cut for the window out of the account receiving customer money and into the company revenue account, PERSIST the batch + its per-job ledger (which marks those jobs swept), and return the file as &#x60;text/plain&#x60; (UTF-8, no BOM). The download filename is &#x60;SCB_file_reference_&lt;first 12 chars of the file ref&gt;.txt&#x60;.  STRUCTURALLY DIFFERENT from the other two streams: an &#x60;OAT&#x60; batch credits ONE destination, so the file carries a SINGLE &#x60;TXNDET&#x60; summing the whole sweep and the per-booking rows are the LEDGER behind that one credit line, not separate recipients. &#x60;recipient_count&#x60; is therefore always 1 and &#x60;job_count&#x60; is the interesting number. The per-transaction bound applies to the WHOLE sweep for the same reason — and an account credit has effectively no bank ceiling, so only the configured &#x60;max_transfer_per_txn&#x60; can bite, at which point the remedy is a narrower day window (the error says so).  CONFIG REQUIRED: the company debit accounts, the fee-charge code, and &#x60;revenue_account&#x60; — the credit destination, which must be an SCB account (10 digits passing the §14 check digit) and is validated both at save time and here. The company NAME is required too (&#x60;TXNDET&#x60; field 13 is mandatory); the company TIN is NOT, because nothing is withheld and no ภ.ง.ด. certificate is emitted.  NO PER-JOB TICK LIST, deliberately: there is one destination, so there is nobody to choose between, and sweeping half a day&#39;s cut would leave the rest looking unswept for a reason nobody could reconstruct later. Send no body to sweep the whole unswept backlog.  409 &#x60;DEDUCTION_ALREADY_SWEPT&#x60; if a concurrent export claimed a job; 409 &#x60;DEDUCTION_BATCH_REF_TAKEN&#x60; if ANY export — payout, refund or sweep — committed in the same Bangkok second (the batch reference has one-second resolution and it is what the bank de-dups a batch on). In both cases the whole transaction rolls back, so NOTHING was marked swept and the same click a moment later succeeds. 400 when the window is invalid, &#x60;value_date&#x60; is in the past, there is nothing to sweep, the total is not a positive transferable amount, or the account config is incomplete. Admin only. 
  ///
  /// Parameters:
  /// * [exportDeductionRequest] 
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [String] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<String>> exportDeductions({ 
    ExportDeductionRequest? exportDeductionRequest,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/admin/deductions/export';
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
      const _type = FullType(ExportDeductionRequest);
      _bodyData = exportDeductionRequest == null ? null : _serializers.serialize(exportDeductionRequest, specifiedType: _type);

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

    String? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : rawResponse as String;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<String>(
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

  /// Generate + download the SCB guard-payout upload file (role&#x3D;admin)
  /// Build ONE SCB Business Net bulk-upload file that pays MANY guards — one &#x60;TXNDET&#x60; per guard inside a single &#x60;BCHDET&#x60; batch (plus a &#x60;WHTCER&#x60; certificate header and its own &#x60;WHTDET&#x60; income-detail record when tax is withheld from that guard), whose totals are the sum of every transfer. PERSIST the batch + a per-booking paid-marker (so no job is ever paid twice), and return the file as &#x60;text/plain&#x60; (UTF-8, no BOM) for download. The download filename is &#x60;SCB_file_reference_&lt;first 12 chars of the file ref&gt;.txt&#x60;.  The request body is OPTIONAL: send none to pay the whole unpaid backlog (every payable guard), or narrow the run with &#x60;guard_ids&#x60; (the admin&#39;s tick list) and/or a &#x60;from&#x60;/&#x60;to&#x60; day window, and optionally pin the &#x60;value_date&#x60;. Guards left out — and guards excluded for a missing/invalid profile or an out-of-bounds amount — are neither written to the file nor marked paid.  409 &#x60;PAYOUT_ALREADY_PAID&#x60; if a concurrent export already claimed a booking, or 409 &#x60;PAYOUT_BATCH_REF_TAKEN&#x60; if ANY export — another payout or a customer refund, since both ride PromptPay off the same one-second clock — committed in the same Bangkok second. The batch reference has one-second resolution, and two files must never share the references the bank de-dups on. The losing export&#39;s whole transaction rolls back, so NOTHING was marked paid and the same click a moment later succeeds. 400 when the selection is empty/invalid, &#x60;value_date&#x60; is in the past, nothing is payable, or the company/debit config is incomplete (including a stored ภ.ง.ด. or fee-charge code outside SCB&#39;s tables). Admin only. 
  ///
  /// Parameters:
  /// * [exportPayoutRequest] 
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [String] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<String>> exportPayout({ 
    ExportPayoutRequest? exportPayoutRequest,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/admin/payouts/export';
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
      const _type = FullType(ExportPayoutRequest);
      _bodyData = exportPayoutRequest == null ? null : _serializers.serialize(exportPayoutRequest, specifiedType: _type);

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

    String? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : rawResponse as String;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<String>(
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

  /// Generate + download the SCB customer-refund upload file (role&#x3D;admin)
  /// Build ONE SCB Business Net bulk-upload file that refunds MANY customers — one &#x60;TXNDET&#x60; per customer inside a single &#x60;BCHDET&#x60; batch, summing every obligation that customer is owed across BOTH lanes — PERSIST the batch + a per-obligation paid-marker, ADVANCE those obligations to &#x60;refund_status &#x3D; &#39;processed&#39;&#x60; in the same transaction, and return the file as &#x60;text/plain&#x60; (UTF-8, no BOM) for download. The download filename is &#x60;SCB_file_reference_&lt;first 12 chars of the file ref&gt;.txt&#x60;.  NO WITHHOLDING. A refund is the customer&#39;s own money coming back, not assessable income, so every line carries &#x60;wht &#x3D; 0&#x60; and the file contains no &#x60;WHTCER&#x60; and no &#x60;WHTDET&#x60;. The ภ.ง.ด. settings and the company tax id are therefore NOT required — only the debit accounts and the fee-charge code from &#x60;/admin/payouts/config&#x60;. The destination is the phone REGISTRATION already captured (the PromptPay &#x60;MOB&#x60; proxy); no new customer PII is collected for refunds.  The request body is OPTIONAL: send none to refund the whole backlog, or narrow the run with &#x60;customer_ids&#x60; (the preview&#39;s tick list) and/or a &#x60;from&#x60;/&#x60;to&#x60; day window, and optionally pin the &#x60;value_date&#x60;. Customers left out — and customers excluded for an unreachable profile or an out-of-bounds amount — are neither written to the file NOR marked processed.  409 &#x60;REFUND_ALREADY_EXPORTED&#x60; if a concurrent export already claimed an obligation, 409 &#x60;REFUND_BATCH_REF_TAKEN&#x60; if ANY export — a refund or a guard payout, since both ride PromptPay off the same one-second clock — committed in the same Bangkok second (the batch reference has one-second resolution, and two files must never share the references the bank de-dups on), or 409 &#x60;REFUND_QUEUE_CHANGED&#x60; if a source row moved underneath the run. In every case the whole transaction rolls back, so NOTHING was marked processed and the same click a moment later succeeds. 400 when the selection is empty/invalid, &#x60;value_date&#x60; is in the past, nothing is refundable, or the debit config is incomplete. Admin only. 
  ///
  /// Parameters:
  /// * [exportRefundRequest] 
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [String] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<String>> exportRefunds({ 
    ExportRefundRequest? exportRefundRequest,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/admin/refunds/export';
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
      const _type = FullType(ExportRefundRequest);
      _bodyData = exportRefundRequest == null ? null : _serializers.serialize(exportRefundRequest, specifiedType: _type);

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

    String? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : rawResponse as String;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<String>(
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

  /// One sweep file + the jobs it collected (role&#x3D;admin)
  /// The batch header plus every job whose cut it collected — the LEDGER behind the file&#39;s single credit line. An item carrying &#x60;voided_at&#x60; is back in the sweepable backlog (the row is kept as history, not deleted). Admin only. 
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
  /// Returns a [Future] containing a [Response] with a [GetDeductionBatch200Response] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<GetDeductionBatch200Response>> getDeductionBatch({ 
    required String id,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/admin/deductions/batches/{id}'.replaceAll('{' r'id' '}', encodeQueryParameter(_serializers, id, const FullType(String)).toString());
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

    GetDeductionBatch200Response? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(GetDeductionBatch200Response),
      ) as GetDeductionBatch200Response;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<GetDeductionBatch200Response>(
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

  /// One payout file + the bookings it paid (role&#x3D;admin)
  /// The batch header plus every per-booking paid-marker it wrote. An item carrying &#x60;voided_at&#x60; belongs to a VOIDED batch: the row is kept as history (the guard was in that file) but the booking is payable again. Admin only. 
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
  /// Returns a [Future] containing a [Response] with a [GetPayoutBatch200Response] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<GetPayoutBatch200Response>> getPayoutBatch({ 
    required String id,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/admin/payouts/batches/{id}'.replaceAll('{' r'id' '}', encodeQueryParameter(_serializers, id, const FullType(String)).toString());
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

    GetPayoutBatch200Response? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(GetPayoutBatch200Response),
      ) as GetPayoutBatch200Response;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<GetPayoutBatch200Response>(
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

  /// Guard-payout settings (role&#x3D;admin)
  /// The single-row company payout settings — the debit accounts the transfers come from + the ภ.ง.ด. withholding terms (form/pay/income type + rate). Blank debit accounts + the standard ภ.ง.ด.53 defaults when unset (never 404s). Admin only. 
  ///
  /// Parameters:
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [GetPayoutConfig200Response] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<GetPayoutConfig200Response>> getPayoutConfig({ 
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/admin/payouts/config';
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

    GetPayoutConfig200Response? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(GetPayoutConfig200Response),
      ) as GetPayoutConfig200Response;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<GetPayoutConfig200Response>(
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

  /// One refund file + the obligations it settled (role&#x3D;admin)
  /// The batch header plus every per-obligation paid-marker it wrote. An item carrying &#x60;voided_at&#x60; was returned to the refundable queue (its source row is &#x60;pending&#x60; again); the row is kept as history rather than deleted. Admin only. 
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
  /// Returns a [Future] containing a [Response] with a [GetRefundBatch200Response] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<GetRefundBatch200Response>> getRefundBatch({ 
    required String id,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/admin/refunds/batches/{id}'.replaceAll('{' r'id' '}', encodeQueryParameter(_serializers, id, const FullType(String)).toString());
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

    GetRefundBatch200Response? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(GetRefundBatch200Response),
      ) as GetRefundBatch200Response;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<GetRefundBatch200Response>(
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

  /// PDPA data export aggregation (service-to-service)
  /// Internal read for identity&#39;s &#x60;ExportClient&#x60; fan-out — aggregates this service&#39;s slice of a user&#39;s PDPA data export. Guarded by a **service-JWT** (&#x60;serviceAuth&#x60;, aud &#x60;pguard-internal&#x60;), never reachable from the public edge (the gateway blocks &#x60;/internal/&#x60;). Returns this service&#39;s per-user export blob (an opaque object). 
  ///
  /// Parameters:
  /// * [userId] 
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [InternalExportUser200Response] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<InternalExportUser200Response>> internalExportUser({ 
    required String userId,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/internal/users/{user_id}/export'.replaceAll('{' r'user_id' '}', encodeQueryParameter(_serializers, userId, const FullType(String)).toString());
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

    InternalExportUser200Response? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(InternalExportUser200Response),
      ) as InternalExportUser200Response;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<InternalExportUser200Response>(
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

  /// Generated platform-cut sweep files (role&#x3D;admin)
  /// The history of generated sweep files, newest first, with the total count for paging. Header rows only — the stored file text is served by &#x60;/admin/deductions/batches/{id}/file&#x60;, and &#x60;has_file&#x60; says whether that re-download will work. Admin only. 
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
  /// Returns a [Future] containing a [Response] with a [ListDeductionBatches200Response] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<ListDeductionBatches200Response>> listDeductionBatches({ 
    int? limit = 50,
    int? offset = 0,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/admin/deductions/batches';
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

    ListDeductionBatches200Response? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(ListDeductionBatches200Response),
      ) as ListDeductionBatches200Response;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<ListDeductionBatches200Response>(
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

  /// Generated payout files (role&#x3D;admin)
  /// The history of generated SCB payout files, newest first, with the total count for paging. Header rows only — the stored file text is served by &#x60;/admin/payouts/batches/{id}/file&#x60;, and &#x60;has_file&#x60; says whether that re-download will work (files generated before the text was stored have no copy). Admin only. 
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
  /// Returns a [Future] containing a [Response] with a [ListPayoutBatches200Response] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<ListPayoutBatches200Response>> listPayoutBatches({ 
    int? limit = 50,
    int? offset = 0,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/admin/payouts/batches';
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

    ListPayoutBatches200Response? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(ListPayoutBatches200Response),
      ) as ListPayoutBatches200Response;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<ListPayoutBatches200Response>(
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

  /// Generated refund files (role&#x3D;admin)
  /// The history of generated SCB refund files, newest first, with the total count for paging. Header rows only — the stored file text is served by &#x60;/admin/refunds/batches/{id}/file&#x60;, and &#x60;has_file&#x60; says whether that re-download will work. Admin only. 
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
  /// Returns a [Future] containing a [Response] with a [ListRefundBatches200Response] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<ListRefundBatches200Response>> listRefundBatches({ 
    int? limit = 50,
    int? offset = 0,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/admin/refunds/batches';
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

    ListRefundBatches200Response? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(ListRefundBatches200Response),
      ) as ListRefundBatches200Response;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<ListRefundBatches200Response>(
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

  /// Preview the platform-cut sweep (role&#x3D;admin)
  /// Stream ② **ยอดที่โดนหักเข้าระบบ** — the itemised cut for the window, before any of it moves. Totals per component (commission / retained cancellation fee / tip / unpaid multi-guard share / proration rounding), the job count, the per-job ledger, and the jobs EXCLUDED because their pricing snapshot is incomplete, each with a Thai reason.  WHAT IS SWEPT: the commission deducted from the guard&#39;s pay, the cancellation fee retained when a customer backs out, the tip, and the billed-but-unpaid share of a multi-guard booking. The last two are in the cut only because of two KNOWN, DEFERRED bugs (the customer is billed a tip the guard never receives; a booking billed for N guards pays exactly one), so they are itemised rather than folded into \&quot;commission\&quot; — fixing either bug moves that figure.  WHAT IS NOT SWEPT, and never will be from here: **VAT** and the **WHT withheld from guards**. Both are the Revenue Department&#39;s money sitting in the same bank account, remitted by e-filing (ภ.พ.30 monthly, ภ.ง.ด.3/53 by the 7th of the following month) — see &#x60;/admin/reports/vat-register&#x60; and &#x60;/admin/reports/wht-payees&#x60;. They are reported here, clearly labelled as excluded, so nobody later \&quot;simplifies\&quot; them into the transfer.  A job whose snapshot is incomplete (a charge predating the VAT split or the pricing snapshot) CANNOT be priced — &#x60;subtotal &#x3D; base_fee × hours × guards + tip&#x60; is one equation in four unknowns — so it is EXCLUDED and COUNTED rather than silently contributing zero, which would under-state the cut. Optional &#x60;from&#x60;/&#x60;to&#x60; narrow the window to the Thai local days the jobs were SETTLED (the same basis the guard-payout backlog uses, so the two halves of one job move together). READ ONLY: persists nothing and marks nothing swept.  &#x60;total_amount&#x60; is what the file would TRANSFER: &#x60;billed_cut_total&#x60; LESS &#x60;uncollected_total&#x60;, the part of those bills the customer never actually paid (the completion reconcile&#39;s &#x60;Extra&#x60; arm records a settled bill above the pre-payment and captures nothing). Both halves are shown rather than the cut quietly shrinking — sweeping money that never arrived would draw down an account that also holds the Revenue Department&#39;s VAT and the guards&#39; unpaid income.  With both ends omitted the window is the WHOLE unswept backlog; if that exceeds what the service will buffer, the response is a typed 400 asking for a narrower window rather than a truncated total. Preview and export are refused identically, so an admin can never export a different set of jobs from the one they previewed. Admin only. 
  ///
  /// Parameters:
  /// * [from] - Inclusive first day the job was settled (Thai local day, `YYYY-MM-DD`).
  /// * [to] - Inclusive last day the job was settled (Thai local day, `YYYY-MM-DD`).
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [PreviewDeductions200Response] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<PreviewDeductions200Response>> previewDeductions({ 
    Date? from,
    Date? to,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/admin/deductions/preview';
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
      if (from != null) r'from': encodeQueryParameter(_serializers, from, const FullType(Date)),
      if (to != null) r'to': encodeQueryParameter(_serializers, to, const FullType(Date)),
    };

    final _response = await _dio.request<Object>(
      _path,
      options: _options,
      queryParameters: _queryParameters,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );

    PreviewDeductions200Response? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(PreviewDeductions200Response),
      ) as PreviewDeductions200Response;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<PreviewDeductions200Response>(
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

  /// Preview the guard-payout batch (role&#x3D;admin)
  /// The UNPAID guard-payout backlog aggregated PER GUARD — who would be paid what (income / WHT withheld / net transfer via PromptPay) — PLUS the guards EXCLUDED from the batch with the reason (no profile row / missing name, tax id, address or a usable PromptPay proxy / a transfer outside SCB&#39;s per-transaction bounds). Every row carries its &#x60;guard_id&#x60; so the screen can tick a subset and pass those ids to the export. Optional &#x60;from&#x60;/&#x60;to&#x60; narrow the backlog to jobs finished within a day window. READ ONLY: computes but persists nothing and marks nothing paid. Admin only. 
  ///
  /// Parameters:
  /// * [from] - Inclusive first day the jobs were finished (Thai local day, `YYYY-MM-DD`).
  /// * [to] - Inclusive last day the jobs were finished (Thai local day, `YYYY-MM-DD`).
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [PreviewPayout200Response] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<PreviewPayout200Response>> previewPayout({ 
    Date? from,
    Date? to,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/admin/payouts/preview';
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
      if (from != null) r'from': encodeQueryParameter(_serializers, from, const FullType(Date)),
      if (to != null) r'to': encodeQueryParameter(_serializers, to, const FullType(Date)),
    };

    final _response = await _dio.request<Object>(
      _path,
      options: _options,
      queryParameters: _queryParameters,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );

    PreviewPayout200Response? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(PreviewPayout200Response),
      ) as PreviewPayout200Response;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<PreviewPayout200Response>(
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

  /// Preview the customer-refund batch (role&#x3D;admin)
  /// The UNREFUNDED backlog aggregated PER CUSTOMER — who would get back how much — PLUS the customers EXCLUDED from the batch with the reason (no customer profile / no name / no usable PromptPay phone / a transfer outside SCB&#39;s per-transaction bounds). Every row carries its &#x60;customer_id&#x60; so the screen can tick a subset and pass those ids to the export.  THE DESTINATION MUST BE A THAI MOBILE. A refund is credited only to a stored phone that is a genuine 10-digit Thai mobile (leading &#x60;0&#x60;) — never to a value that merely happens to be 13 or 15 digits long, which SCB would stamp &#x60;NAT&#x60;/&#x60;EWL&#x60; and PromptPay to whoever owns that id. A customer whose stored phone is anything else is EXCLUDED with a reason asking for it to be corrected, and nothing of theirs is marked processed. (The guard payout is deliberately more permissive: a guard&#39;s proxy is a tax id they supplied as a payment address.)  TWO LANES are summed into each row and both are covered: &#x60;payment.payments&#x60; (&#x60;refund_status &#x3D; &#39;pending&#39;&#x60; with &#x60;refund_amount &gt; 0&#x60; — the completion-reconcile overpay, the cancellation refund, the race-lost pre-pay compensator) and &#x60;payment.payment_slips&#x60; (&#x60;applied &#x3D; false&#x60; and pending — a genuine double-transfer for an already-paid booking).  Optional &#x60;from&#x60;/&#x60;to&#x60; narrow the backlog to obligations that became owed within a Thai local day window. READ ONLY: computes but persists nothing and marks nothing processed. Admin only. 
  ///
  /// Parameters:
  /// * [from] - Inclusive first day the refund became owed (Thai local day, `YYYY-MM-DD`).
  /// * [to] - Inclusive last day the refund became owed (Thai local day, `YYYY-MM-DD`).
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [PreviewRefunds200Response] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<PreviewRefunds200Response>> previewRefunds({ 
    Date? from,
    Date? to,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/admin/refunds/preview';
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
      if (from != null) r'from': encodeQueryParameter(_serializers, from, const FullType(Date)),
      if (to != null) r'to': encodeQueryParameter(_serializers, to, const FullType(Date)),
    };

    final _response = await _dio.request<Object>(
      _path,
      options: _options,
      queryParameters: _queryParameters,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );

    PreviewRefunds200Response? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(PreviewRefunds200Response),
      ) as PreviewRefunds200Response;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<PreviewRefunds200Response>(
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

  /// Record where a sweep file got to at the bank (role&#x3D;admin)
  /// &#x60;generated → uploaded → confirmed | rejected&#x60;, enforced by the ONE shared transition table. &#x60;confirmed&#x60; and &#x60;voided&#x60; are TERMINAL. &#x60;voided&#x60; is refused here by name (400): voiding must also release every job in the batch and must carry a reason, so it has its own endpoint — coming through this door it would flip the header while leaving the jobs claimed, i.e. never sweepable again. Admin only. 
  ///
  /// Parameters:
  /// * [id] 
  /// * [setDeductionBatchStatusRequest] 
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [SetDeductionBatchStatus200Response] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<SetDeductionBatchStatus200Response>> setDeductionBatchStatus({ 
    required String id,
    required SetDeductionBatchStatusRequest setDeductionBatchStatusRequest,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/admin/deductions/batches/{id}/status'.replaceAll('{' r'id' '}', encodeQueryParameter(_serializers, id, const FullType(String)).toString());
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
      const _type = FullType(SetDeductionBatchStatusRequest);
      _bodyData = _serializers.serialize(setDeductionBatchStatusRequest, specifiedType: _type);

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

    SetDeductionBatchStatus200Response? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(SetDeductionBatchStatus200Response),
      ) as SetDeductionBatchStatus200Response;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<SetDeductionBatchStatus200Response>(
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

  /// Record where a payout file got to at the bank (role&#x3D;admin)
  /// Move the batch along its lifecycle: &#x60;generated → uploaded → confirmed | rejected&#x60;. Each step stamps its own timestamp, so the batch keeps the full history. Admin only.  &#x60;voided&#x60; is NOT accepted here (400): a void must also un-mark every item — that is what returns the bookings to the payable backlog — and must carry a reason, so it has its own endpoint. An illegal step is a typed 409: &#x60;PAYOUT_BATCH_TERMINAL&#x60; (the batch is &#x60;confirmed&#x60; or &#x60;voided&#x60; — a confirmed batch is money that already moved and can never be re-opened), &#x60;PAYOUT_BATCH_ALREADY_VOIDED&#x60;, or &#x60;PAYOUT_BATCH_TRANSITION&#x60;. 
  ///
  /// Parameters:
  /// * [id] 
  /// * [setPayoutBatchStatusRequest] 
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [SetPayoutBatchStatus200Response] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<SetPayoutBatchStatus200Response>> setPayoutBatchStatus({ 
    required String id,
    required SetPayoutBatchStatusRequest setPayoutBatchStatusRequest,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/admin/payouts/batches/{id}/status'.replaceAll('{' r'id' '}', encodeQueryParameter(_serializers, id, const FullType(String)).toString());
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
      const _type = FullType(SetPayoutBatchStatusRequest);
      _bodyData = _serializers.serialize(setPayoutBatchStatusRequest, specifiedType: _type);

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

    SetPayoutBatchStatus200Response? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(SetPayoutBatchStatus200Response),
      ) as SetPayoutBatchStatus200Response;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<SetPayoutBatchStatus200Response>(
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

  /// Record where a refund file got to at the bank (role&#x3D;admin)
  /// Move the batch along its lifecycle: &#x60;generated → uploaded → confirmed | rejected&#x60;. Each step stamps its own timestamp, so the batch keeps the full history. Admin only.  &#x60;voided&#x60; is NOT accepted here (400): a void must also un-mark every item AND flip its source row back to &#x60;pending&#x60; — that is what returns the money to the queue — and must carry a reason, so it has its own endpoint. An illegal step is a typed 409: &#x60;REFUND_BATCH_TERMINAL&#x60; (the batch is &#x60;confirmed&#x60; or &#x60;voided&#x60; — a confirmed batch is money that already moved and can never be re-opened), &#x60;REFUND_BATCH_ALREADY_VOIDED&#x60;, or &#x60;REFUND_BATCH_TRANSITION&#x60;. 
  ///
  /// Parameters:
  /// * [id] 
  /// * [setRefundBatchStatusRequest] 
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [SetRefundBatchStatus200Response] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<SetRefundBatchStatus200Response>> setRefundBatchStatus({ 
    required String id,
    required SetRefundBatchStatusRequest setRefundBatchStatusRequest,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/admin/refunds/batches/{id}/status'.replaceAll('{' r'id' '}', encodeQueryParameter(_serializers, id, const FullType(String)).toString());
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
      const _type = FullType(SetRefundBatchStatusRequest);
      _bodyData = _serializers.serialize(setRefundBatchStatusRequest, specifiedType: _type);

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

    SetRefundBatchStatus200Response? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(SetRefundBatchStatus200Response),
      ) as SetRefundBatchStatus200Response;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<SetRefundBatchStatus200Response>(
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

  /// Save guard-payout settings (role&#x3D;admin)
  /// Incremental — a field left null keeps the stored value (or the schema default on first write). Admin only.
  ///
  /// Parameters:
  /// * [updatePayoutConfigRequest] 
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [GetPayoutConfig200Response] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<GetPayoutConfig200Response>> updatePayoutConfig({ 
    required UpdatePayoutConfigRequest updatePayoutConfigRequest,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/admin/payouts/config';
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
      const _type = FullType(UpdatePayoutConfigRequest);
      _bodyData = _serializers.serialize(updatePayoutConfigRequest, specifiedType: _type);

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

    GetPayoutConfig200Response? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(GetPayoutConfig200Response),
      ) as GetPayoutConfig200Response;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<GetPayoutConfig200Response>(
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

  /// Output-VAT register (รายงานภาษีขาย) for one month — ภ.พ.30 (role&#x3D;admin)
  /// One line per settled payment that charged VAT: the Thai calendar day the customer PAID, the payment/booking/customer ids, the VAT-exclusive subtotal and the VAT; plus the period totals an accountant transcribes onto the ภ.พ.30 form.  BUCKETED ON &#x60;paid_at&#x60;, and it matters: Thai VAT on a service has its tax point at RECEIPT OF PAYMENT, and it is the same basis &#x60;/admin/reports/revenue&#x60; uses, so the register and the revenue chart tie out line for line. (The platform-cut sweep buckets on the settle timestamp instead — a different question. The three streams can only be reconciled because each says which basis it uses.) The AMOUNTS are the SETTLED split, so a job paid in one month and prorated in the next reports its final VAT in the month it was paid.  The customer is reported as an ID, not a name: resolving names would be a cross-service fan-out per row on a report that runs to thousands of rows a month, and the admin panel already has a batch resolver (&#x60;POST /admin/users/resolve&#x60;).  &#x60;format&#x3D;csv&#x60; returns the spreadsheet an accountant works in — rendered SERVER-SIDE with RFC 4180 quoting, a UTF-8 BOM (without it Excel on Thai Windows renders Thai as mojibake) and formula neutralisation (including a lead hidden behind leading whitespace or a control byte, which spreadsheet importers strip before parsing the cell), plus a TOTAL row.  A month with more rows than the service will buffer is a typed 400 asking for a narrower period, never a truncated list — a short VAT total is a number an accountant would file. Admin only. 
  ///
  /// Parameters:
  /// * [month] - The filing period, `YYYY-MM` (Thai calendar month). Required — a defaulted period on a tax report is a filing for the wrong month.
  /// * [format] - `csv` for the spreadsheet; omitted or anything else returns JSON.
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [VatRegisterReport200Response] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<VatRegisterReport200Response>> vatRegisterReport({ 
    required String month,
    String? format,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/admin/reports/vat-register';
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
      r'month': encodeQueryParameter(_serializers, month, const FullType(String)),
      if (format != null) r'format': encodeQueryParameter(_serializers, format, const FullType(String)),
    };

    final _response = await _dio.request<Object>(
      _path,
      options: _options,
      queryParameters: _queryParameters,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );

    VatRegisterReport200Response? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(VatRegisterReport200Response),
      ) as VatRegisterReport200Response;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<VatRegisterReport200Response>(
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

  /// Cancel a sweep file and return its jobs to the backlog (role&#x3D;admin)
  /// The escape hatch from the one-way door: a batch whose file was lost (or that the bank refused) would otherwise leave its jobs marked swept — cut recorded as collected with no money moved — with only a hand-written UPDATE to undo it. Flips the header to &#x60;voided&#x60; and releases EVERY live job, which is what puts them back in the sweepable backlog. The reason is REQUIRED.  A CONFIRMED batch cannot be voided (409 &#x60;DEDUCTION_BATCH_TERMINAL&#x60;): the money moved, so releasing its jobs would sweep the same cut a second time. The remedy for a confirmed batch that was wrong is a correcting transfer, or the per-item void below. Admin only. 
  ///
  /// Parameters:
  /// * [id] 
  /// * [voidDeductionBatchRequest] 
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [SetDeductionBatchStatus200Response] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<SetDeductionBatchStatus200Response>> voidDeductionBatch({ 
    required String id,
    required VoidDeductionBatchRequest voidDeductionBatchRequest,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/admin/deductions/batches/{id}/void'.replaceAll('{' r'id' '}', encodeQueryParameter(_serializers, id, const FullType(String)).toString());
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
      const _type = FullType(VoidDeductionBatchRequest);
      _bodyData = _serializers.serialize(voidDeductionBatchRequest, specifiedType: _type);

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

    SetDeductionBatchStatus200Response? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(SetDeductionBatchStatus200Response),
      ) as SetDeductionBatchStatus200Response;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<SetDeductionBatchStatus200Response>(
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

  /// Return SOME of a sweep&#39;s jobs to the backlog (role&#x3D;admin)
  /// Release the NAMED jobs, leaving every other job in the file collected and the batch&#39;s own status untouched. The trigger is not a failed credit line (an &#x60;OAT&#x60; file has ONE line, which the bank takes or does not): it is a job that should never have been collected — a settled row later found to be wrong, or a sweep run over a window an admin did not mean.  **REFUSED ONCE THE BATCH IS &#x60;confirmed&#x60; (409 &#x60;DEDUCTION_BATCH_CONFIRMED&#x60;) — the OPPOSITE of the payout and refund files.** Theirs carry one credit line PER RECIPIENT, so an individual PromptPay credit can genuinely bounce inside a file the bank accepted and releasing that one item is right. This file carries ONE credit line for the whole batch, so &#x60;confirmed&#x60; means the entire summed amount moved into the revenue account; releasing a job would return its cut to the backlog and the next sweep would move it a SECOND time. The correct remedies, which the Thai error names, are a whole-batch void (if the money truly did not move) or a manual accounting adjustment (if it did).  On every other status it works, and the reason is mandatory: the audit record carries it plus the released amount, which is what ties this file&#39;s stated total to the next sweep&#39;s.  404 if a named job is not in THIS batch; 409 &#x60;DEDUCTION_ITEM_ALREADY_VOIDED&#x60; if one was already released. Admin only. 
  ///
  /// Parameters:
  /// * [id] 
  /// * [voidDeductionBatchItemsRequest] 
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [GetDeductionBatch200Response] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<GetDeductionBatch200Response>> voidDeductionBatchItems({ 
    required String id,
    required VoidDeductionBatchItemsRequest voidDeductionBatchItemsRequest,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/admin/deductions/batches/{id}/items/void'.replaceAll('{' r'id' '}', encodeQueryParameter(_serializers, id, const FullType(String)).toString());
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
      const _type = FullType(VoidDeductionBatchItemsRequest);
      _bodyData = _serializers.serialize(voidDeductionBatchItemsRequest, specifiedType: _type);

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

    GetDeductionBatch200Response? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(GetDeductionBatch200Response),
      ) as GetDeductionBatch200Response;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<GetDeductionBatch200Response>(
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

  /// Void a payout file and return its work to the backlog (role&#x3D;admin)
  /// Cancel a batch that never reached the bank (or that the bank refused) and RETURN every booking in it to the payable backlog, so the guards can be paid by a fresh file. The item rows are kept as history (flagged &#x60;voided_at&#x60;), not deleted — the paid-marker unique is partial on that flag, which is what makes those bookings payable again.  &#x60;reason&#x60; is REQUIRED and must be non-blank: a void moves money back into the queue, and six months later a void with no reason cannot be told apart from a mis-click. A &#x60;confirmed&#x60; batch can NEVER be voided (the transfers went out — un-marking would pay those guards a second time) and a second void is a typed 409, not a silent success. Admin only. 
  ///
  /// Parameters:
  /// * [id] 
  /// * [voidPayoutBatchRequest] 
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [SetPayoutBatchStatus200Response] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<SetPayoutBatchStatus200Response>> voidPayoutBatch({ 
    required String id,
    required VoidPayoutBatchRequest voidPayoutBatchRequest,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/admin/payouts/batches/{id}/void'.replaceAll('{' r'id' '}', encodeQueryParameter(_serializers, id, const FullType(String)).toString());
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
      const _type = FullType(VoidPayoutBatchRequest);
      _bodyData = _serializers.serialize(voidPayoutBatchRequest, specifiedType: _type);

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

    SetPayoutBatchStatus200Response? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(SetPayoutBatchStatus200Response),
      ) as SetPayoutBatchStatus200Response;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<SetPayoutBatchStatus200Response>(
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

  /// Return SOME of a payout file&#39;s bookings to the backlog (role&#x3D;admin)
  /// Put the named bookings back in the payable backlog while every OTHER booking in the file stays paid and the batch&#39;s own status is left alone. Admin only.  This is the remedy for the everyday partial failure: SCB can ACCEPT a bulk file and still fail individual credit lines — an unregistered PromptPay proxy, or one not linked to a receiving account, is the usual cause. The file is structurally valid, so the batch is honestly &#x60;confirmed&#x60;; a handful of guards simply never got their money. Voiding the WHOLE batch would un-pay the guards who DID get paid, and is refused outright once the batch is &#x60;confirmed&#x60;.  It therefore works at ANY batch status, &#x60;confirmed&#x60; included, and deliberately does not walk the lifecycle state machine: the status records what the bank did with the FILE (still true), while this records which BOOKINGS it actually paid. &#x60;reason&#x60; is REQUIRED and non-blank — this is the record of why money the ledger says was paid is queued to be paid again.  Rejections are typed, never a partial success: 400 for an empty &#x60;booking_ids&#x60; (that would be the whole-batch action) or a blank reason, 404 when a &#x60;booking_id&#x60; is not in THIS batch, 409 &#x60;PAYOUT_ITEM_ALREADY_VOIDED&#x60; when one was already returned. 
  ///
  /// Parameters:
  /// * [id] 
  /// * [voidPayoutBatchItemsRequest] 
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [GetPayoutBatch200Response] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<GetPayoutBatch200Response>> voidPayoutBatchItems({ 
    required String id,
    required VoidPayoutBatchItemsRequest voidPayoutBatchItemsRequest,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/admin/payouts/batches/{id}/items/void'.replaceAll('{' r'id' '}', encodeQueryParameter(_serializers, id, const FullType(String)).toString());
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
      const _type = FullType(VoidPayoutBatchItemsRequest);
      _bodyData = _serializers.serialize(voidPayoutBatchItemsRequest, specifiedType: _type);

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

    GetPayoutBatch200Response? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(GetPayoutBatch200Response),
      ) as GetPayoutBatch200Response;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<GetPayoutBatch200Response>(
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

  /// Void a refund file and return its obligations to the queue (role&#x3D;admin)
  /// Cancel a refund file that never reached the bank (or that the bank refused) and RETURN every obligation in it to the refundable queue, so those customers can be paid by a fresh file. Both halves happen: the item rows are flagged &#x60;voided_at&#x60; (kept as history — the paid-marker unique is partial on that flag) AND each source row goes back to &#x60;refund_status &#x3D; &#39;pending&#39;&#x60;. Either half alone would leave the customer permanently unrefunded.  &#x60;reason&#x60; is REQUIRED and must be non-blank: a void moves money back into the queue, and six months later a void with no reason cannot be told apart from a mis-click. A &#x60;confirmed&#x60; batch can NEVER be voided (the transfers went out — un-marking would refund those customers a second time) and a second void is a typed 409, not a silent success. Admin only. 
  ///
  /// Parameters:
  /// * [id] 
  /// * [voidRefundBatchRequest] 
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [SetRefundBatchStatus200Response] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<SetRefundBatchStatus200Response>> voidRefundBatch({ 
    required String id,
    required VoidRefundBatchRequest voidRefundBatchRequest,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/admin/refunds/batches/{id}/void'.replaceAll('{' r'id' '}', encodeQueryParameter(_serializers, id, const FullType(String)).toString());
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
      const _type = FullType(VoidRefundBatchRequest);
      _bodyData = _serializers.serialize(voidRefundBatchRequest, specifiedType: _type);

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

    SetRefundBatchStatus200Response? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(SetRefundBatchStatus200Response),
      ) as SetRefundBatchStatus200Response;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<SetRefundBatchStatus200Response>(
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

  /// Return SOME of a refund file&#39;s obligations to the queue (role&#x3D;admin)
  /// Put the named obligations back in the refundable queue while every OTHER obligation in the file stays settled and the batch&#39;s own status is left alone. Admin only.  This is the remedy for the everyday partial failure: SCB can ACCEPT a bulk file and still fail individual credit lines — a PromptPay proxy not linked to a receiving account is the usual cause. The file is structurally valid, so the batch is honestly &#x60;confirmed&#x60;; a handful of customers simply never got their money. Voiding the WHOLE batch would un-settle the ones who DID, and is refused outright once the batch is &#x60;confirmed&#x60;.  It therefore works at ANY batch status, &#x60;confirmed&#x60; included, and deliberately does not walk the lifecycle state machine: the status records what the bank did with the FILE (still true), while this records which OBLIGATIONS it actually settled. &#x60;reason&#x60; is REQUIRED and non-blank.  Each obligation is named by the &#x60;(source_kind, source_id)&#x60; PAIR the batch drill-down reports — a bare id would be ambiguous, because &#x60;payment&#x60; and &#x60;slip&#x60; are separate tables with separate id spaces. Rejections are typed, never a partial success: 400 for an empty &#x60;sources&#x60; (that would be the whole-batch action), an unknown &#x60;source_kind&#x60; or a blank reason; 404 when an obligation is not in THIS batch; 409 &#x60;REFUND_ITEM_ALREADY_VOIDED&#x60; when one was already returned. 
  ///
  /// Parameters:
  /// * [id] 
  /// * [voidRefundBatchItemsRequest] 
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [GetRefundBatch200Response] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<GetRefundBatch200Response>> voidRefundBatchItems({ 
    required String id,
    required VoidRefundBatchItemsRequest voidRefundBatchItemsRequest,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/admin/refunds/batches/{id}/items/void'.replaceAll('{' r'id' '}', encodeQueryParameter(_serializers, id, const FullType(String)).toString());
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
      const _type = FullType(VoidRefundBatchItemsRequest);
      _bodyData = _serializers.serialize(voidRefundBatchItemsRequest, specifiedType: _type);

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

    GetRefundBatch200Response? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(GetRefundBatch200Response),
      ) as GetRefundBatch200Response;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<GetRefundBatch200Response>(
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

  /// ภ.ง.ด.3/53 payee list for one month (role&#x3D;admin)
  /// Every guard who had tax withheld from a payout in the period, with their TIN, name, address, the income type, the gross assessable income paid and the tax withheld — plus the period totals. This reads &#x60;payout_batch_items.wht&#x60;, which has been WRITE-ONLY since the payout shipped: the one figure the law requires us to report was previously unreachable from the running system.  BUCKETED ON the payout batch&#39;s &#x60;value_date&#x60; — the day the transfer settles is the day the payment to the payee is made, which is the month the filing covers (due by the 7th of the following month). Not the file&#39;s creation date: generating a file on the 31st for a value date of the 1st would file the withholding a month early.  ONLY BATCHES WHOSE MONEY ACTUALLY MOVED ARE COUNTED — money that was never paid was never withheld, and a return that declares withholding which did not occur is an over-declaration to the Revenue Department with a payee certificate nobody can match. Status by status: &#x60;generated&#x60; IN (the certificate is produced and the file is on its way; if it never lands the admin voids it, which removes it here), &#x60;uploaded&#x60; IN, &#x60;confirmed&#x60; IN, **&#x60;rejected&#x60; OUT** (the bank refused the file — not one baht was transferred), &#x60;voided&#x60; OUT. Individually voided ITEMS are excluded too, which is what covers a per-item void on an otherwise-good batch.  A capped-out month is a typed 400 telling the admin to narrow the period, never a silently truncated list: a short tax return looks exactly like a correct one.  &#x60;form_type_code&#x60; and &#x60;income_type_code&#x60; are reported exactly as stored in the payout config — which ภ.ง.ด. form applies is the operator&#39;s TAX decision, and a report that silently corrected it would be filing something other than what was certified to the payee. A payee whose profile is missing is STILL LISTED with blank PII, because the withholding happened.  &#x60;format&#x3D;csv&#x60; as above (server-rendered, BOM&#39;d, with a TOTAL row). Admin only. 
  ///
  /// Parameters:
  /// * [month] - The filing period, `YYYY-MM` (Thai calendar month).
  /// * [format] - `csv` for the spreadsheet; omitted or anything else returns JSON.
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [WhtPayeeReport200Response] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<WhtPayeeReport200Response>> whtPayeeReport({ 
    required String month,
    String? format,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/admin/reports/wht-payees';
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
      r'month': encodeQueryParameter(_serializers, month, const FullType(String)),
      if (format != null) r'format': encodeQueryParameter(_serializers, format, const FullType(String)),
    };

    final _response = await _dio.request<Object>(
      _path,
      options: _options,
      queryParameters: _queryParameters,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );

    WhtPayeeReport200Response? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(WhtPayeeReport200Response),
      ) as WhtPayeeReport200Response;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<WhtPayeeReport200Response>(
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
