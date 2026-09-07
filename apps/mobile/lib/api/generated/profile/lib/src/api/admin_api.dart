//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

import 'dart:async';

import 'package:built_value/json_object.dart';
import 'package:built_value/serializer.dart';
import 'package:dio/dio.dart';

import 'package:pguard_profile_api/src/api_util.dart';
import 'package:pguard_profile_api/src/model/admin_avg_approval_time200_response.dart';
import 'package:pguard_profile_api/src/model/admin_get_org_settings200_response.dart';
import 'package:pguard_profile_api/src/model/admin_list_access_audit200_response.dart';
import 'package:pguard_profile_api/src/model/admin_list_candidates200_response.dart';
import 'package:pguard_profile_api/src/model/admin_list_customer_profiles200_response.dart';
import 'package:pguard_profile_api/src/model/admin_list_expiring_documents200_response.dart';
import 'package:pguard_profile_api/src/model/admin_list_guard_profiles200_response.dart';
import 'package:pguard_profile_api/src/model/admin_list_support_tickets200_response.dart';
import 'package:pguard_profile_api/src/model/admin_pending_applicants_count200_response.dart';
import 'package:pguard_profile_api/src/model/admin_resolve_user_names200_response.dart';
import 'package:pguard_profile_api/src/model/admin_set_candidate_stage200_response.dart';
import 'package:pguard_profile_api/src/model/approval_status.dart';
import 'package:pguard_profile_api/src/model/error_body.dart';
import 'package:pguard_profile_api/src/model/inline_object.dart';
import 'package:pguard_profile_api/src/model/inline_object2.dart';
import 'package:pguard_profile_api/src/model/internal_customer_payout_profile200_response.dart';
import 'package:pguard_profile_api/src/model/internal_export_user200_response.dart';
import 'package:pguard_profile_api/src/model/internal_guard_payout_profile200_response.dart';
import 'package:pguard_profile_api/src/model/internal_list_guards200_response.dart';
import 'package:pguard_profile_api/src/model/internal_org_settings200_response.dart';
import 'package:pguard_profile_api/src/model/internal_pending_roles200_response.dart';
import 'package:pguard_profile_api/src/model/reject_request.dart';
import 'package:pguard_profile_api/src/model/resolve_names_request.dart';
import 'package:pguard_profile_api/src/model/stage_request.dart';
import 'package:pguard_profile_api/src/model/update_guard_payout_request.dart';
import 'package:pguard_profile_api/src/model/update_org_settings_request.dart';

class AdminApi {

  final Dio _dio;

  final Serializers _serializers;

  const AdminApi(this._dio, this._serializers);

  /// Approve a pending customer profile (role&#x3D;admin)
  /// Moves the customer profile &#x60;pending → approved&#x60; via the pure approval transition (the customer mirror of the guard approve). Emits &#x60;user.approved&#x60; (transactional outbox) so identity unblocks the customer&#39;s login. Approved is terminal: re-approving or moving an already-finalized profile returns 409. Admin only (else 403). Returns the updated customer profile. 
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
  /// Returns a [Future] containing a [Response] with a [InlineObject2] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<InlineObject2>> adminApproveCustomer({ 
    required String userId,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/admin/customer-profiles/{user_id}/approve'.replaceAll('{' r'user_id' '}', encodeQueryParameter(_serializers, userId, const FullType(String)).toString());
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

  /// Approve a pending guard profile (role&#x3D;admin)
  /// Moves the guard profile &#x60;pending → approved&#x60; via the pure approval transition. Approved is terminal: re-approving or moving an already-finalized profile returns 409. Admin only (else 403). Returns the updated profile (FULL account number). 
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
  /// Returns a [Future] containing a [Response] with a [InlineObject] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<InlineObject>> adminApproveGuard({ 
    required String userId,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/admin/guard-profiles/{user_id}/approve'.replaceAll('{' r'user_id' '}', encodeQueryParameter(_serializers, userId, const FullType(String)).toString());
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

  /// Average guard approval turnaround (role&#x3D;admin)
  /// เวลาอนุมัติเฉลี่ย (#132): the mean of &#x60;reviewed_at - created_at&#x60; over APPROVED guards, in seconds + a pre-rounded hours value, with the &#x60;sample_size&#x60;. &#x60;avg_seconds&#x60;/&#x60;avg_hours&#x60; are &#x60;null&#x60; (and &#x60;sample_size&#x60; 0) when no guard has been approved yet — an honest empty state, not a fake 0h. &#x60;reviewed_at&#x60; is the dedicated approval-decision timestamp (never clobbered by a guard self-edit). Admin only (else 403); replica read. 
  ///
  /// Parameters:
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [AdminAvgApprovalTime200Response] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<AdminAvgApprovalTime200Response>> adminAvgApprovalTime({ 
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/admin/applicants/avg-approval-time';
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

    AdminAvgApprovalTime200Response? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(AdminAvgApprovalTime200Response),
      ) as AdminAvgApprovalTime200Response;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<AdminAvgApprovalTime200Response>(
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

  /// Read the organization (company) profile (role&#x3D;admin)
  /// The org (company) profile — &#x60;company_name&#x60; / &#x60;tax_id&#x60; / &#x60;address&#x60; — shown on RECEIPTS and IN-APP (#143, Settings → บริษัท / Company profile). This is org-wide, admin-owned config (edited at runtime, no redeploy), so unlike the env-config Settings tabs it has a real single-row store owned by the profile service. Admin only (else 403).  WHY THE THREE FIELDS MATTER: they are the SELLER block that a Thai full tax invoice (ใบเสร็จรับเงิน/ใบกำกับภาษี) is legally required to carry — the issuer&#39;s name, TIN (เลขประจำตัวผู้เสียภาษี) and registered address. While they are null, every receipt the platform issues is missing its issuer block and is not a valid tax invoice, even though VAT 7% was collected from the customer.  NEVER 404s: when nothing has been saved yet, every field is &#x60;null&#x60; and &#x60;updated_at&#x60; is &#x60;null&#x60; (an \&quot;unset\&quot; default) — the admin UI renders blank inputs and warns that receipts are incomplete. Reading the company profile is org config, not PII, so it is NOT §30 access-audited. 
  ///
  /// Parameters:
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [AdminGetOrgSettings200Response] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<AdminGetOrgSettings200Response>> adminGetOrgSettings({ 
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/admin/org-settings';
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

    AdminGetOrgSettings200Response? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(AdminGetOrgSettings200Response),
      ) as AdminGetOrgSettings200Response;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<AdminGetOrgSettings200Response>(
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

  /// List the PDPA §30 data-access audit trail (role&#x3D;admin)
  /// Who (an admin) accessed what PII and when — the §30 access trail written by the admin list endpoints. Newest first, optional &#x60;action&#x60; filter + limit/offset. Admin only. NOTE: this is a DATA-ACCESS trail, not a full business-action feed (approved/refund/ check-in with actor/IP/payload) — that needs a dedicated audit-event sink. 
  ///
  /// Parameters:
  /// * [action] - Filter by the recorded action (e.g. admin_list_guard_profiles).
  /// * [limit] 
  /// * [offset] 
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [AdminListAccessAudit200Response] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<AdminListAccessAudit200Response>> adminListAccessAudit({ 
    String? action,
    int? limit = 50,
    int? offset = 0,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/admin/access-audit';
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
      if (action != null) r'action': encodeQueryParameter(_serializers, action, const FullType(String)),
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

    AdminListAccessAudit200Response? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(AdminListAccessAudit200Response),
      ) as AdminListAccessAudit200Response;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<AdminListAccessAudit200Response>(
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

  /// List guards as recruitment-pipeline candidates (role&#x3D;admin)
  /// Every guard as a lean pipeline candidate (no PII). The kanban groups pending guards by &#x60;recruitment_stage&#x60; (sourcing/screened/docs_verified) and finalized ones by &#x60;approval_status&#x60; — approve/reject reuse the existing guard-profile endpoints. Admin only. 
  ///
  /// Parameters:
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [AdminListCandidates200Response] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<AdminListCandidates200Response>> adminListCandidates({ 
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/admin/recruitment/candidates';
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

    AdminListCandidates200Response? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(AdminListCandidates200Response),
      ) as AdminListCandidates200Response;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<AdminListCandidates200Response>(
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

  /// List customer profiles (role&#x3D;admin)
  /// Lists customer profiles, newest first (capped at 200, not paginated), optionally filtered by &#x60;approval_status&#x60;. Admin only (else 403). Each row carries &#x60;approval_status&#x60; (pending/approved/rejected) so the admin can see who is still awaiting review — customers are now admin-approved exactly like guards (no longer auto-approved on first profile insert). The ผู้สมัคร page&#39;s \&quot;ผู้เรียก รปภ.\&quot; (customer) tab passes &#x60;?approval_status&#x3D;pending&#x60;. Records a PDPA §30 read-audit row.  Each row also carries &#x60;login_phone&#x60; (the account&#39;s own number, resolved from identity) — distinct from the optional, often-blank &#x60;contact_phone&#x60; on the profile itself. 
  ///
  /// Parameters:
  /// * [approvalStatus] - Filter by status. An unrecognized value returns 400.
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [AdminListCustomerProfiles200Response] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<AdminListCustomerProfiles200Response>> adminListCustomerProfiles({ 
    ApprovalStatus? approvalStatus,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/admin/customer-profiles';
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
      if (approvalStatus != null) r'approval_status': encodeQueryParameter(_serializers, approvalStatus, const FullType(ApprovalStatus)),
    };

    final _response = await _dio.request<Object>(
      _path,
      options: _options,
      queryParameters: _queryParameters,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );

    AdminListCustomerProfiles200Response? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(AdminListCustomerProfiles200Response),
      ) as AdminListCustomerProfiles200Response;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<AdminListCustomerProfiles200Response>(
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

  /// List guard documents needing renewal + urgency buckets (role&#x3D;admin)
  /// Guard documents expiring within the &#x60;window&#x60; (days; INCLUDING already-expired), soonest first — each carrying &#x60;days_left&#x60; (negative &#x3D; expired). The response also returns window-INDEPENDENT &#x60;buckets&#x60; (expired / due_7 / due_30 / due_90) for the dashboard pills, so the counts don&#39;t change as the admin narrows the list. Admin only (else 403); replica read. Rows are populated by the guard profile submit (&#x60;POST /profile/guard&#x60;, which folds in the registration doc step&#39;s expiry dates) — empty until that capture lands. 
  ///
  /// Parameters:
  /// * [window] - List filter (days). One of 7, 30, 90 (default 90). Any other value → 400.
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [AdminListExpiringDocuments200Response] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<AdminListExpiringDocuments200Response>> adminListExpiringDocuments({ 
    int? window = 90,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/admin/documents/expiring';
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
      if (window != null) r'window': encodeQueryParameter(_serializers, window, const FullType(int)),
    };

    final _response = await _dio.request<Object>(
      _path,
      options: _options,
      queryParameters: _queryParameters,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );

    AdminListExpiringDocuments200Response? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(AdminListExpiringDocuments200Response),
      ) as AdminListExpiringDocuments200Response;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<AdminListExpiringDocuments200Response>(
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

  /// List guard profiles for onboarding review (role&#x3D;admin; FULL bank details)
  /// Lists guard profiles, newest first, optionally filtered by &#x60;approval_status&#x60;. Admin only (else 403). **Returns the FULL, UN-masked &#x60;account_number&#x60;** — the reviewer needs it to verify payout details.  Rows are &#x60;GuardProfileAdmin&#x60;: the profile PLUS &#x60;created_at&#x60; (signup time) and &#x60;login_phone&#x60; (the account&#39;s own number, resolved from identity) so the approval queue can show a reachable human instead of a short id. 
  ///
  /// Parameters:
  /// * [approvalStatus] - Filter by status. An unrecognized value returns 400.
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [AdminListGuardProfiles200Response] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<AdminListGuardProfiles200Response>> adminListGuardProfiles({ 
    ApprovalStatus? approvalStatus,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/admin/guard-profiles';
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
      if (approvalStatus != null) r'approval_status': encodeQueryParameter(_serializers, approvalStatus, const FullType(ApprovalStatus)),
    };

    final _response = await _dio.request<Object>(
      _path,
      options: _options,
      queryParameters: _queryParameters,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
      onReceiveProgress: onReceiveProgress,
    );

    AdminListGuardProfiles200Response? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(AdminListGuardProfiles200Response),
      ) as AdminListGuardProfiles200Response;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<AdminListGuardProfiles200Response>(
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

  /// List support tickets, newest first (role&#x3D;admin)
  /// The admin queue of support tickets filed from the mobile Help page — newest first (&#x60;created_at DESC&#x60;), limit/offset paged. Admin only (else **403**). Each row carries the reporter&#39;s &#x60;user_id&#x60;; the web admin maps it to a display name with the existing batch name-resolver (&#x60;POST /admin/users/resolve&#x60;). Replica read. 
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
  /// Returns a [Future] containing a [Response] with a [AdminListSupportTickets200Response] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<AdminListSupportTickets200Response>> adminListSupportTickets({ 
    int? limit = 50,
    int? offset = 0,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/admin/support/tickets';
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

    AdminListSupportTickets200Response? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(AdminListSupportTickets200Response),
      ) as AdminListSupportTickets200Response;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<AdminListSupportTickets200Response>(
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

  /// Count guards + customers awaiting approval (role&#x3D;admin)
  /// New-applicants count for the dashboard notification card + the ผู้สมัคร page (#132): how many guards AND customers are pending admin approval (&#x60;approval_status &#x3D; &#39;pending&#39;&#x60;), plus the total. Both roles now share the same admin-review gate (customers are no longer auto-approved), so the per-role split drives the page&#39;s two tabs and &#x60;total&#x60; is the badge. Admin only (else 403); replica read. 
  ///
  /// Parameters:
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [AdminPendingApplicantsCount200Response] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<AdminPendingApplicantsCount200Response>> adminPendingApplicantsCount({ 
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/admin/applicants/pending-count';
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

    AdminPendingApplicantsCount200Response? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(AdminPendingApplicantsCount200Response),
      ) as AdminPendingApplicantsCount200Response;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<AdminPendingApplicantsCount200Response>(
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

  /// Reject a pending customer profile (role&#x3D;admin)
  /// Moves the customer profile &#x60;pending → rejected&#x60; via the pure approval transition (the customer mirror of the guard reject). May carry an optional &#x60;reason&#x60;. Rejected is terminal (409 on a finalized profile). Admin only (else 403). Returns the updated customer profile. 
  ///
  /// Parameters:
  /// * [userId] 
  /// * [rejectRequest] 
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [InlineObject2] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<InlineObject2>> adminRejectCustomer({ 
    required String userId,
    RejectRequest? rejectRequest,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/admin/customer-profiles/{user_id}/reject'.replaceAll('{' r'user_id' '}', encodeQueryParameter(_serializers, userId, const FullType(String)).toString());
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
      const _type = FullType(RejectRequest);
      _bodyData = rejectRequest == null ? null : _serializers.serialize(rejectRequest, specifiedType: _type);

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

  /// Reject a pending guard profile (role&#x3D;admin)
  /// Moves the guard profile &#x60;pending → rejected&#x60; via the pure approval transition. May carry an optional &#x60;reason&#x60;. Rejected is terminal (409 on a finalized profile). Admin only (else 403). Returns the updated profile (FULL account number). 
  ///
  /// Parameters:
  /// * [userId] 
  /// * [rejectRequest] 
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [InlineObject] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<InlineObject>> adminRejectGuard({ 
    required String userId,
    RejectRequest? rejectRequest,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/admin/guard-profiles/{user_id}/reject'.replaceAll('{' r'user_id' '}', encodeQueryParameter(_serializers, userId, const FullType(String)).toString());
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
      const _type = FullType(RejectRequest);
      _bodyData = rejectRequest == null ? null : _serializers.serialize(rejectRequest, specifiedType: _type);

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

  /// Batch-resolve user_ids to display names (role&#x3D;admin)
  /// Resolve a batch of &#x60;user_id&#x60;s to display names for the admin lists that otherwise render raw UUIDs — จัดการงาน/jobs (guard_id + customer_id), รีวิว/reviews (guard_id + customer_id), บันทึกการโทร/calls (caller + callee), and the Activity Log (admin user_id). **Admin only** (role gate at the gateway-routed edge + this service; non-admin → **403**).  profile OWNS the guard/customer display names (&#x60;guard_profiles.full_name&#x60; / &#x60;customer_profiles.full_name&#x60;), answered in ONE query. For the ids it CAN&#39;T resolve locally (almost always ADMINS — who have no profile row here — or unknown/deleted ids) it then asks identity&#39;s service-JWT&#39;d &#x60;POST /internal/users/names&#x60; and MERGES the admin &#x60;{ role: admin, display_name }&#x60; entries into the same map (#142 Activity Log). Best-effort: an identity outage degrades to \&quot;admin ids omitted\&quot; (client fallback) rather than failing the resolve.  The response is a MAP keyed by id → &#x60;{ role, display_name }&#x60;:   - a guard/customer id resolves to its name + the role derived from which table it is in     (&#x60;display_name&#x60; may be &#x60;null&#x60; mid-onboarding — the role is still authoritative);   - an admin id resolves to &#x60;{ role: admin, display_name }&#x60; merged from identity;   - an id with NO row in EITHER place (genuinely unknown / deleted) is simply **OMITTED**     from the map — the client renders a fallback (role label + short id) for it.  Returns ONLY &#x60;{ role, display_name }&#x60; — NEVER any other PII (phone / bank / address / email). Bounded to &#x60;RESOLVE_NAMES_LIMIT&#x60; (500) ids per call — a larger batch → **400** (page it), not a silent truncation (a partial map is indistinguishable from \&quot;these ids are unknown\&quot;). Duplicate ids are de-duplicated server-side; an empty &#x60;ids&#x60; list → an empty map (&#x60;{}&#x60;). 
  ///
  /// Parameters:
  /// * [resolveNamesRequest] 
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [AdminResolveUserNames200Response] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<AdminResolveUserNames200Response>> adminResolveUserNames({ 
    required ResolveNamesRequest resolveNamesRequest,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/admin/users/resolve';
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
      const _type = FullType(ResolveNamesRequest);
      _bodyData = _serializers.serialize(resolveNamesRequest, specifiedType: _type);

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

    AdminResolveUserNames200Response? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(AdminResolveUserNames200Response),
      ) as AdminResolveUserNames200Response;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<AdminResolveUserNames200Response>(
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

  /// Move a pending candidate to a pipeline stage (role&#x3D;admin)
  /// Sets a PENDING guard&#39;s pre-approval &#x60;recruitment_stage&#x60;. A finalized (approved/rejected) candidate returns 409 — they leave the pipeline via approval_status, not this. An unknown stage returns 400. Admin only. This stage gates nothing (it&#39;s admin-workflow metadata). 
  ///
  /// Parameters:
  /// * [userId] 
  /// * [stageRequest] 
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [AdminSetCandidateStage200Response] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<AdminSetCandidateStage200Response>> adminSetCandidateStage({ 
    required String userId,
    required StageRequest stageRequest,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/admin/recruitment/candidates/{user_id}/stage'.replaceAll('{' r'user_id' '}', encodeQueryParameter(_serializers, userId, const FullType(String)).toString());
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
      const _type = FullType(StageRequest);
      _bodyData = _serializers.serialize(stageRequest, specifiedType: _type);

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

    AdminSetCandidateStage200Response? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(AdminSetCandidateStage200Response),
      ) as AdminSetCandidateStage200Response;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<AdminSetCandidateStage200Response>(
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

  /// Set a guard&#39;s payout fields — tax id + bank (role&#x3D;admin)
  /// Sets the fields a guard PAYOUT needs but the guard&#39;s own registration never captures: &#x60;tax_id&#x60; (the Thai national/tax id — both the PromptPay **NAT** proxy and the ภ.ง.ด. recipient TIN) and the bank block. Without a &#x60;tax_id&#x60; no guard is payable, so &#x60;POST /admin/payouts/export&#x60; returned 400 for every guard until an operator filled this in.  **Incremental (COALESCE-merge)** — a field that is ABSENT *or* &#x60;null&#x60; keeps the stored value, exactly like &#x60;PUT /admin/payouts/config&#x60;: typing in a tax id can never blank out bank details the operator never saw. Clearing a field is therefore NOT expressible here; that belongs to the guard&#39;s own &#x60;PUT /profile/guard&#x60;.  &#x60;tax_id&#x60; carries the GUARD validation rule — 8–20 digits with separators, PLUS a Thai national-id **mod-11 checksum on exactly 13 digits** (400 otherwise). 13 digits is the PromptPay &#x60;NAT&#x60; proxy the payout file credits and PromptPay is irreversible, so a well-shaped but mistyped id is rejected here rather than paid to a stranger. This is STRICTER than the company &#x60;tax_id&#x60; on &#x60;PUT /admin/org-settings&#x60; — see that operation for why the two rules must stay separate.  Admin only (else 403). 404 when that user has no guard profile — this never INSERTS one. Returns the FULL (unmasked) profile so the operator can verify what they typed. The write is PDPA §30-audited (&#x60;admin_update_guard_payout&#x60;) — it touches the two most sensitive columns on the row, so \&quot;who set this national id\&quot; must be answerable. 
  ///
  /// Parameters:
  /// * [userId] 
  /// * [updateGuardPayoutRequest] 
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [InlineObject] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<InlineObject>> adminUpdateGuardPayout({ 
    required String userId,
    required UpdateGuardPayoutRequest updateGuardPayoutRequest,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/admin/guard-profiles/{user_id}/payout'.replaceAll('{' r'user_id' '}', encodeQueryParameter(_serializers, userId, const FullType(String)).toString());
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
      const _type = FullType(UpdateGuardPayoutRequest);
      _bodyData = _serializers.serialize(updateGuardPayoutRequest, specifiedType: _type);

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

  /// Set/replace the organization (company) profile (role&#x3D;admin)
  /// Upsert the single-row org (company) profile. Admin only (else 403). All fields optional (the admin saves incrementally). Validates a LENIENT &#x60;tax_id&#x60; (8–20 digits, spaces/hyphens allowed — **shape only, no checksum**) and bounded &#x60;company_name&#x60;/&#x60;address&#x60; lengths (≤ 500 chars); an invalid value → 400. The acting admin is recorded server-side (&#x60;updated_by&#x60;). Returns the stored row for read-back.  The lenient rule is load-bearing, not an oversight: this is a JURISTIC-PERSON TIN, so the citizen mod-11 checksum that gates a GUARD&#39;s &#x60;tax_id&#x60; does not apply — and because this form re-sends the value it loaded, enforcing it would make the screen unsavable for any install holding a non-conforming TIN, which in turn blocks the payout export (it 400s with no company tax id). See &#x60;UpdateOrgSettingsRequest.tax_id&#x60;. 
  ///
  /// Parameters:
  /// * [updateOrgSettingsRequest] 
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [AdminGetOrgSettings200Response] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<AdminGetOrgSettings200Response>> adminUpdateOrgSettings({ 
    required UpdateOrgSettingsRequest updateOrgSettingsRequest,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/admin/org-settings';
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
      const _type = FullType(UpdateOrgSettingsRequest);
      _bodyData = _serializers.serialize(updateOrgSettingsRequest, specifiedType: _type);

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

    AdminGetOrgSettings200Response? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(AdminGetOrgSettings200Response),
      ) as AdminGetOrgSettings200Response;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<AdminGetOrgSettings200Response>(
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

  /// Customer REFUND destination (service-to-service)
  /// The customer PII payment needs to build ONE recipient row in the **customer refund** SCB file (stream ①, ยอดที่ต้องโอนคืนคนจ้าง, &#x60;PPY&#x60;): name, PromptPay phone, address.  **Auth:** service-JWT only (&#x60;serviceAuth&#x60;, aud &#x60;pguard-internal&#x60;); blocked at the public edge like every &#x60;/internal/&#x60; route.  **Deliberately narrower than the guard twin: NO &#x60;tax_id&#x60; is returned at all.** A refund is the customer&#39;s own money coming back, not income — no withholding, therefore no recipient TIN, therefore nothing here that could leak one. Per the locked product decision the refund destination is whatever REGISTRATION already captured; no new PII is collected for refunds.  **404 semantics:** &#x60;404&#x60; when there is NO customer profile row for &#x60;user_id&#x60;. Same rule as the guard read — exclude that ONE customer from the batch with a reason and carry on; a 404 must never fail the refund run or become a transfer to a blank destination.  **&#x60;phone&#x60; is BEST-EFFORT and never an error.** &#x60;customer_profiles.contact_phone&#x60; wins when set (it is the number the customer chose to be contacted on, so the refund and its notification land in the same place); a blank/whitespace value falls back to the account&#39;s LOGIN phone from identity, which is &#x60;NOT NULL&#x60; over there. The identity hop is only made when &#x60;contact_phone&#x60; is blank. An identity outage degrades &#x60;phone&#x60; to whatever the profile row holds — possibly &#x60;null&#x60; — and this endpoint still returns **200**. &#x60;phone: null&#x60; means UNREFUNDABLE: exclude that customer, do not substitute anything.  **No normalisation** — RAW as stored, same contract as the guard read (see above for why). 
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
  /// Returns a [Future] containing a [Response] with a [InternalCustomerPayoutProfile200Response] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<InternalCustomerPayoutProfile200Response>> internalCustomerPayoutProfile({ 
    required String userId,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/internal/customers/{user_id}/payout-profile'.replaceAll('{' r'user_id' '}', encodeQueryParameter(_serializers, userId, const FullType(String)).toString());
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

    InternalCustomerPayoutProfile200Response? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(InternalCustomerPayoutProfile200Response),
      ) as InternalCustomerPayoutProfile200Response;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<InternalCustomerPayoutProfile200Response>(
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

  /// Guard payout destination + WHT recipient block (service-to-service)
  /// The guard PII payment needs to build ONE recipient row in the **guard payout** SCB file (stream ③, &#x60;PPY&#x60;) and its ภ.ง.ด.53 recipient block: name, FULL tax id, address, phone.  **Auth:** service-JWT only (&#x60;serviceAuth&#x60;, aud &#x60;pguard-internal&#x60;). The gateway blocks &#x60;/internal/&#x60; at the public edge, so this is unreachable from a user token.  **This is one of only TWO surfaces in the system that return an UNMASKED tax id** (the other being the customer twin below, which returns none at all — so in practice it is the only one). Every owner- and admin-facing profile read masks &#x60;tax_id&#x60; to its last 4 digits under PDPA. Treat the response as PII: do not log it, do not forward it to a user-facing payload.  **404 semantics:** &#x60;404&#x60; when there is NO guard profile row for &#x60;guard_id&#x60; — it does NOT mean \&quot;unpayable\&quot; and does not distinguish a deleted user from a never-onboarded one. The caller must exclude that ONE guard from the batch with a reason and continue; a 404 must never fail the whole payout run, and must never be retried into a blank recipient.  **&#x60;phone&#x60; is BEST-EFFORT and never an error.** It is the guard&#39;s LOGIN phone, resolved from identity (profile does not store it — &#x60;emergency_contact_phone&#x60; is someone ELSE&#39;s number and must never be paid to). It is the PromptPay &#x60;MOB&#x60; fallback proxy used when the guard has no tax id (a Thai login number is 10 digits — &#x60;CPX_Toolkit_Reverse_Engineering.md&#x60;:2055, PPY proxy by length: 15→&#x60;EWL&#x60;, 13→&#x60;NAT&#x60;, 10→&#x60;MOB&#x60;). If identity is unreachable, degraded, or mid-rollout on an older build, &#x60;phone&#x60; comes back &#x60;null&#x60; and this endpoint still returns **200** — an unrelated service being down must not fail a payout batch. The caller then excludes that one guard (no tax id AND no phone ⇒ no destination).  **No normalisation.** Values are returned RAW, exactly as stored; payment owns &#x60;digits_only&#x60; at its writer boundary. Two internal reads disagreeing on who normalises is how a proxy silently changes LENGTH — and therefore proxy TYPE — between streams. 
  ///
  /// Parameters:
  /// * [guardId] 
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [InternalGuardPayoutProfile200Response] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<InternalGuardPayoutProfile200Response>> internalGuardPayoutProfile({ 
    required String guardId,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/internal/guards/{guard_id}/payout-profile'.replaceAll('{' r'guard_id' '}', encodeQueryParameter(_serializers, guardId, const FullType(String)).toString());
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

    InternalGuardPayoutProfile200Response? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(InternalGuardPayoutProfile200Response),
      ) as InternalGuardPayoutProfile200Response;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<InternalGuardPayoutProfile200Response>(
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

  /// Approved guard catalog (service-to-service)
  /// Internal read for booking&#39;s discovery (&#x60;/available-guards&#x60;) — the APPROVED guard catalog. Guarded by a **service-JWT** (&#x60;ServiceCaller&#x60;), never reachable from the public edge (the gateway blocks &#x60;/internal/&#x60;). Returns ONLY &#x60;{ user_id, years_of_experience }&#x60; — least-privilege; the PDPA-sensitive bank/PII columns never cross the wire. Documented here for the contract; not part of the user-facing client. 
  ///
  /// Parameters:
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [InternalListGuards200Response] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<InternalListGuards200Response>> internalListGuards({ 
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/internal/guards';
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

    InternalListGuards200Response? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(InternalListGuards200Response),
      ) as InternalListGuards200Response;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<InternalListGuards200Response>(
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

  /// Company (WHT payer) block for the bank files (service-to-service)
  /// The company block payment stamps onto every SCB file header and the ภ.ง.ด.53 payer section: legal &#x60;company_name&#x60;, the company &#x60;tax_id&#x60; (payer TIN) and the registered &#x60;address&#x60;, read from the single &#x60;profile.org_settings&#x60; row.  **Auth:** service-JWT only (&#x60;serviceAuth&#x60;, aud &#x60;pguard-internal&#x60;); blocked at the public edge.  **NEVER 404 — that is the point.** When the org profile has never been saved this returns **200** with all three fields &#x60;null&#x60; (the \&quot;unset\&quot; state), not a not-found. The caller can then surface an actionable \&quot;configure the company profile first\&quot; error instead of a bare 404 that reads as a bug. A &#x60;tax_id&#x60; of &#x60;null&#x60; here is what makes &#x60;POST /admin/payouts/export&#x60; refuse to produce a file.  The &#x60;tax_id&#x60; returned is the COMPANY (juristic-person) number, validated shape-only — see &#x60;UpdateOrgSettingsRequest.tax_id&#x60; for why the citizen mod-11 checksum deliberately does not apply to it. It is a tax REFERENCE, never a transfer destination, and is not masked on any read (unlike a guard&#39;s). 
  ///
  /// Parameters:
  /// * [cancelToken] - A [CancelToken] that can be used to cancel the operation
  /// * [headers] - Can be used to add additional headers to the request
  /// * [extras] - Can be used to add flags to the request
  /// * [validateStatus] - A [ValidateStatus] callback that can be used to determine request success based on the HTTP status of the response
  /// * [onSendProgress] - A [ProgressCallback] that can be used to get the send progress
  /// * [onReceiveProgress] - A [ProgressCallback] that can be used to get the receive progress
  ///
  /// Returns a [Future] containing a [Response] with a [InternalOrgSettings200Response] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<InternalOrgSettings200Response>> internalOrgSettings({ 
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/internal/org-settings';
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

    InternalOrgSettings200Response? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(InternalOrgSettings200Response),
      ) as InternalOrgSettings200Response;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<InternalOrgSettings200Response>(
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

  /// Roles with a submitted-but-pending profile (service-to-service)
  /// Internal read for identity: the roles this user has SUBMITTED a profile for that are NOT yet approved (&#x60;approval_status &#x3D; &#39;pending&#39;&#x60; in &#x60;guard_profiles&#x60;/&#x60;customer_profiles&#x60;). identity calls this (over a **service-JWT**, &#x60;serviceAuth&#x60;, blocked at the public edge) to enrich &#x60;GET /auth/me&#x60; with &#x60;pending_roles&#x60;, so the mobile mode-picker shows a submitted role as \&quot;pending approval\&quot; instead of re-offering its blank registration form. Returns &#x60;[]&#x60; when nothing is pending. 
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
  /// Returns a [Future] containing a [Response] with a [InternalPendingRoles200Response] as data
  /// Throws [DioException] if API call or serialization fails
  Future<Response<InternalPendingRoles200Response>> internalPendingRoles({ 
    required String userId,
    CancelToken? cancelToken,
    Map<String, dynamic>? headers,
    Map<String, dynamic>? extra,
    ValidateStatus? validateStatus,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    final _path = r'/internal/users/{user_id}/pending-roles'.replaceAll('{' r'user_id' '}', encodeQueryParameter(_serializers, userId, const FullType(String)).toString());
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

    InternalPendingRoles200Response? _responseData;

    try {
      final rawResponse = _response.data;
      _responseData = rawResponse == null ? null : _serializers.deserialize(
        rawResponse,
        specifiedType: const FullType(InternalPendingRoles200Response),
      ) as InternalPendingRoles200Response;

    } catch (error, stackTrace) {
      throw DioException(
        requestOptions: _response.requestOptions,
        response: _response,
        type: DioExceptionType.unknown,
        error: error,
        stackTrace: stackTrace,
      );
    }

    return Response<InternalPendingRoles200Response>(
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
