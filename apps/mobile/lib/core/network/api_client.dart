import 'package:dio/dio.dart';

import '../config/app_config.dart';
import '../storage/secure_store.dart';
import 'api_exception.dart';
import 'jwt.dart';

/// The REST surface controllers depend on. Returns the UNWRAPPED `data` field of the
/// `{ success, error, data }` envelope, or throws [ApiException]. An interface so controllers
/// can be unit-tested against a fake without Dio/HTTP.
abstract class PguardApi {
  Future<dynamic> get(String path, {Map<String, dynamic>? query});

  /// POST `path`. When [bearer] is supplied (e.g. the single-use `profile_token` during
  /// registration, before the user can log in), it is sent as the `Authorization` header
  /// verbatim and the normal session-token attach + proactive/reactive refresh is SKIPPED
  /// (there is no session yet, and the token is purpose-scoped).
  Future<dynamic> post(String path, {Object? data, String? bearer});
  Future<dynamic> put(String path, {Object? data});
  Future<dynamic> patch(String path, {Object? data});
  Future<dynamic> delete(String path, {Object? data});

  /// A non-expired access token, refreshing proactively if needed (or `null` if there is no
  /// usable session). The WebSocket layer uses this so each (re)connect carries a fresh Bearer
  /// instead of a stale stored token.
  Future<String?> validAccessToken();
}

/// Dio-backed [PguardApi] talking to the api-gateway `/v1` edge.
///
/// Auth handling (mirrors v1's hybrid strategy, CLAUDE.md proactive-refresh decision):
///  - **Bearer attach**: non-public requests get `Authorization: Bearer <access>`.
///  - **Proactive refresh**: if the access token expires within [AppConfig.proactiveRefreshLeeway]
///    (2 min), refresh BEFORE sending so the request rarely 401s.
///  - **Reactive 401**: a 401 that slips through triggers exactly one refresh + retry.
///  - **Single-flight**: concurrent requests share one in-flight refresh (no token stampede).
/// Refresh uses a SEPARATE bare Dio so it never recurses through this interceptor.
class ApiClient implements PguardApi {
  ApiClient({
    required SessionStore store,
    Dio? dio,
    Dio? refreshDio,
    DateTime Function()? clock,
    this.onAuthLost,
  })  : _store = store,
        _dio = dio ?? Dio(),
        _refreshDio = refreshDio ?? Dio(),
        _clock = clock ?? (() => DateTime.now().toUtc()) {
    final base = BaseOptions(
      baseUrl: AppConfig.apiBaseUrl,
      connectTimeout: AppConfig.connectTimeout,
      receiveTimeout: AppConfig.receiveTimeout,
      // Treat 4xx (except 401) as a "valid" response so `_send` can surface it as a clean
      // ApiException. A 401 is DELIBERATELY excluded so it becomes a DioException and reaches
      // the `_onError` interceptor, which runs the one-shot reactive refresh + retry (cloning a
      // FormData body so multipart uploads survive the retry). Without this, a 401 would be a
      // normal response and `_onError` would never fire — the reactive path would be dead and a
      // token revoked mid-session (still structurally valid, so proactive refresh doesn't catch
      // it) would bounce the user to login instead of refreshing seamlessly.
      validateStatus: (s) => s != null && s < 500 && s != 401,
      contentType: Headers.jsonContentType,
    );
    _dio.options = base;
    _refreshDio.options = BaseOptions(
      baseUrl: AppConfig.apiBaseUrl,
      connectTimeout: AppConfig.connectTimeout,
      receiveTimeout: AppConfig.receiveTimeout,
      contentType: Headers.jsonContentType,
    );
    _dio.interceptors.add(
      InterceptorsWrapper(onRequest: _onRequest, onError: _onError),
    );
  }

  final SessionStore _store;
  final Dio _dio;
  final Dio _refreshDio;
  final DateTime Function() _clock;

  /// Invoked when a refresh attempt fails and the session is dropped, so the app can route
  /// back to the lock/login screen instead of sitting in a zombie "authenticated" state.
  /// [reasonCode] carries the server's machine-readable rejection code when one was given —
  /// notably `SESSION_SUPERSEDED` (this device was kicked by a newer login on another device)
  /// so the login screen can say WHY instead of silently demanding the PIN again.
  final void Function({String? reasonCode})? onAuthLost;

  /// In-flight refresh shared by all callers (single-flight). Resolves to the new access
  /// token, or `null` if refresh failed.
  Future<String?>? _refreshing;

  /// Paths that must NOT carry a Bearer and must NOT trigger refresh (they mint tokens / run
  /// pre-session). `/auth/register` is token-minting (it returns a profile_token, not a session)
  /// and runs before the user can log in — never attach a (possibly stale) access token to it.
  ///
  /// `/auth/reset-pin` belongs here for the same reason and was missing: it authenticates with the
  /// single-use `phone_verified_token` from a just-completed OTP, NOT with a session. Someone who
  /// has genuinely forgotten their PIN has no session at all, so treating it as authenticated sent
  /// the interceptor off to refresh a token that isn't there — the forgot-PIN flow failed before
  /// the request was ever sent. It also revokes every session server-side as it succeeds, so any
  /// Bearer we attached would be dead by the time the response came back.
  static bool _isPublic(String path) {
    return path.startsWith('/otp/') ||
        path == '/auth/login' ||
        path == '/auth/refresh' ||
        path == '/auth/register' ||
        path == '/auth/reset-pin';
  }

  // ---------- interceptors ----------

  /// Requests carrying an explicit `bearer` (registration profile_token) set this so the
  /// interceptor neither attaches the session token nor refreshes on 401 (no session exists).
  static const _noSessionAuth = 'pg_no_session_auth';

  Future<void> _onRequest(
      RequestOptions options, RequestInterceptorHandler handler) async {
    // Public (token-minting) paths and explicit-bearer requests carry no session token and
    // never trigger refresh — the caller's Authorization header (if any) is already set.
    if (_isPublic(options.path) || options.extra[_noSessionAuth] == true) {
      return handler.next(options);
    }
    var access = await _store.readAccessToken();
    // Proactive refresh: if missing/expiring, refresh before sending.
    if (access == null ||
        Jwt.isExpiredOrExpiring(
          access,
          leeway: AppConfig.proactiveRefreshLeeway,
          now: _clock(),
        )) {
      access = await _refreshAccessToken();
    }
    if (access != null) {
      options.headers['Authorization'] = 'Bearer $access';
    }
    return handler.next(options);
  }

  Future<void> _onError(
      DioException err, ErrorInterceptorHandler handler) async {
    final response = err.response;
    final options = err.requestOptions;
    final alreadyRetried = options.extra['pg_retried'] == true;
    // One reactive refresh+retry on a 401 for a protected, not-yet-retried request. An
    // explicit-bearer request (registration profile_token) has no session to refresh — let its
    // 401 surface as-is (a bad/expired/consumed profile_token).
    if (response?.statusCode == 401 &&
        !alreadyRetried &&
        !_isPublic(options.path) &&
        options.extra[_noSessionAuth] != true) {
      final access = await _refreshAccessToken(force: true);
      if (access != null) {
        options.extra['pg_retried'] = true;
        options.headers['Authorization'] = 'Bearer $access';
        // A multipart body finalizes on first send — re-sending the same FormData throws a
        // StateError. Clone it so one-refresh-and-retry also covers attachment uploads.
        if (options.data is FormData) {
          options.data = (options.data as FormData).clone();
        }
        try {
          final retried = await _dio.fetch(options);
          return handler.resolve(retried);
        } on DioException catch (e) {
          return handler.next(e);
        }
      }
    }
    return handler.next(err);
  }

  /// Refresh the access token (single-flight). [force] bypasses nothing here but documents
  /// the reactive caller. Returns the new access token, or `null` on failure (and clears the
  /// session so the app routes back to the lock/login screen).
  Future<String?> _refreshAccessToken({bool force = false}) {
    return _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);
  }

  Future<String?> _doRefresh() async {
    final refresh = await _store.readRefreshToken();
    // No session to lose — don't fire onAuthLost.
    if (refresh == null) {
      return null;
    }
    try {
      final res = await _refreshDio.post<dynamic>(
        '/auth/refresh',
        data: {'refresh_token': refresh},
      );
      final data = _unwrap(res);
      if (data is Map<String, dynamic>) {
        final access = data['access_token'] as String?;
        final newRefresh = data['refresh_token'] as String?;
        if (access != null && newRefresh != null) {
          await _store.saveTokens(access: access, refresh: newRefresh);
          return access;
        }
      }
      await _sessionLost();
      return null;
    } on DioException catch (e) {
      // Drop the session ONLY on a genuine auth rejection — the refresh token itself was rejected
      // (invalid / expired / reuse-detected → 401/403). A TRANSIENT failure (no response, timeout,
      // connection error, or a 5xx — e.g. identity restarting during a deploy, or a flaky network)
      // must NOT log the user out: keep the still-valid refresh token and let the next request
      // retry. Dropping the session on a network blip is what logged BOTH devices out during a
      // deploy even though their 7-day refresh tokens were still valid server-side.
      final status = e.response?.statusCode;
      if (status == 401 || status == 403) {
        await _sessionLost(reasonCode: _rejectionCode(e.response));
      }
      return null;
    }
  }

  /// The machine-readable `error.code` off a refresh rejection body, if the server sent one
  /// (e.g. `SESSION_SUPERSEDED` — kicked by a newer login on another device).
  static String? _rejectionCode(Response<dynamic>? res) {
    final body = res?.data;
    if (body is Map<String, dynamic>) {
      final err = body['error'];
      if (err is Map<String, dynamic>) return err['code'] as String?;
    }
    return null;
  }

  /// A real session was lost mid-flight (refresh rejected): clear the TOKENS and notify the app
  /// so the router leaves the dashboard. Deliberately [SessionStore.clearTokens], NOT
  /// `clearSession` — the wider clear also deleted the remembered PHONE before
  /// `Session.logout()` could capture it, which made the device classify as brand-new and
  /// forced the OTP + SET-A-NEW-PIN flow instead of the returning PIN-login. Session teardown
  /// (phone capture → returning) is owned by the [onAuthLost] handler.
  Future<void> _sessionLost({String? reasonCode}) async {
    await _store.clearTokens();
    onAuthLost?.call(reasonCode: reasonCode);
  }

  @override
  Future<String?> validAccessToken() async {
    var access = await _store.readAccessToken();
    if (access == null ||
        Jwt.isExpiredOrExpiring(
          access,
          leeway: AppConfig.proactiveRefreshLeeway,
          now: _clock(),
        )) {
      access = await _refreshAccessToken();
    }
    return access;
  }

  // ---------- public API ----------

  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? query}) => _send(
        () => _dio.get<dynamic>(
          path,
          queryParameters: query,
          // Interactive reads surface a failure fast (perf-review #13) — the shorter receive window
          // applies to GETs only; uploads keep the client's default (longer) receiveTimeout.
          options: Options(receiveTimeout: AppConfig.interactiveReceiveTimeout),
        ),
      );

  @override
  Future<dynamic> post(String path, {Object? data, String? bearer}) => _send(
        () => _dio.post<dynamic>(
          path,
          data: data,
          options: bearer == null
              ? null
              : Options(
                  headers: {'Authorization': 'Bearer $bearer'},
                  extra: {_noSessionAuth: true},
                ),
        ),
      );

  @override
  Future<dynamic> put(String path, {Object? data}) =>
      _send(() => _dio.put<dynamic>(path, data: data));

  @override
  Future<dynamic> patch(String path, {Object? data}) =>
      _send(() => _dio.patch<dynamic>(path, data: data));

  @override
  Future<dynamic> delete(String path, {Object? data}) =>
      _send(() => _dio.delete<dynamic>(path, data: data));

  Future<dynamic> _send(Future<Response<dynamic>> Function() call) async {
    try {
      final res = await call();
      // 4xx EXCEPT 401 lands here as a normal response (validateStatus) — surface as
      // ApiException. A 401 is a DioException handled by `_onError` (reactive refresh+retry); if
      // that retry doesn't recover it, it arrives in the `on DioException` branch below.
      final status = res.statusCode ?? 0;
      if (status >= 400) {
        throw _errorFromResponse(res);
      }
      return _unwrap(res);
    } on DioException catch (e) {
      throw _errorFromDio(e);
    }
  }

  /// Pull the `data` field out of the `{ success, error, data }` envelope.
  static dynamic _unwrap(Response<dynamic> res) {
    final body = res.data;
    if (body is Map<String, dynamic> && body.containsKey('data')) {
      return body['data'];
    }
    return body;
  }

  ApiException _errorFromResponse(Response<dynamic> res) {
    final body = res.data;
    String message = 'Request failed';
    String? code;
    if (body is Map<String, dynamic>) {
      final err = body['error'];
      if (err is Map<String, dynamic>) {
        message = (err['message'] as String?) ?? message;
        code = err['code'] as String?;
      } else if (err is String) {
        message = err;
      }
    }
    return ApiException(
        message: message, code: code, statusCode: res.statusCode);
  }

  ApiException _errorFromDio(DioException e) {
    final res = e.response;
    if (res != null) return _errorFromResponse(res);
    return const ApiException(
      message: 'Network error — please check your connection',
      statusCode: null,
    );
  }
}
