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
  Future<dynamic> post(String path, {Object? data});
  Future<dynamic> put(String path, {Object? data});

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
      // We validate status codes ourselves so the interceptor can react to 401.
      validateStatus: (s) => s != null && s < 500,
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
  final void Function()? onAuthLost;

  /// In-flight refresh shared by all callers (single-flight). Resolves to the new access
  /// token, or `null` if refresh failed.
  Future<String?>? _refreshing;

  /// Paths that must NOT carry a Bearer and must NOT trigger refresh (they mint tokens).
  static bool _isPublic(String path) {
    return path.startsWith('/otp/') ||
        path == '/auth/login' ||
        path == '/auth/refresh';
  }

  // ---------- interceptors ----------

  Future<void> _onRequest(
      RequestOptions options, RequestInterceptorHandler handler) async {
    if (_isPublic(options.path)) {
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
    // One reactive refresh+retry on a 401 for a protected, not-yet-retried request.
    if (response?.statusCode == 401 &&
        !alreadyRetried &&
        !_isPublic(options.path)) {
      final access = await _refreshAccessToken(force: true);
      if (access != null) {
        options.extra['pg_retried'] = true;
        options.headers['Authorization'] = 'Bearer $access';
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
    } on DioException {
      // Reuse-detected / expired / network: drop the session; UI re-authenticates.
      await _sessionLost();
      return null;
    }
  }

  /// A real session was lost mid-flight (refresh rejected): clear tokens AND notify the app so
  /// the router leaves the dashboard. Without the callback the UI would zombie on stale state.
  Future<void> _sessionLost() async {
    await _store.clearSession();
    onAuthLost?.call();
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
  Future<dynamic> get(String path, {Map<String, dynamic>? query}) =>
      _send(() => _dio.get<dynamic>(path, queryParameters: query));

  @override
  Future<dynamic> post(String path, {Object? data}) =>
      _send(() => _dio.post<dynamic>(path, data: data));

  @override
  Future<dynamic> put(String path, {Object? data}) =>
      _send(() => _dio.put<dynamic>(path, data: data));

  Future<dynamic> _send(Future<Response<dynamic>> Function() call) async {
    try {
      final res = await call();
      // 4xx with validateStatus<500 lands here as a normal response — surface as ApiException.
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
