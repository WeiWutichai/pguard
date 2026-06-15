//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

import 'package:dio/dio.dart';
import 'package:built_value/serializer.dart';
import 'package:pguard_notification_api/src/serializers.dart';
import 'package:pguard_notification_api/src/auth/api_key_auth.dart';
import 'package:pguard_notification_api/src/auth/basic_auth.dart';
import 'package:pguard_notification_api/src/auth/bearer_auth.dart';
import 'package:pguard_notification_api/src/auth/oauth.dart';
import 'package:pguard_notification_api/src/api/broadcast_api.dart';
import 'package:pguard_notification_api/src/api/fcm_tokens_api.dart';
import 'package:pguard_notification_api/src/api/internal_api.dart';
import 'package:pguard_notification_api/src/api/notifications_api.dart';

class PguardNotificationApi {
  static const String basePath = r'https://api.pguard.app/v1';

  final Dio dio;
  final Serializers serializers;

  PguardNotificationApi({
    Dio? dio,
    Serializers? serializers,
    String? basePathOverride,
    List<Interceptor>? interceptors,
  })  : this.serializers = serializers ?? standardSerializers,
        this.dio = dio ??
            Dio(BaseOptions(
              baseUrl: basePathOverride ?? basePath,
              connectTimeout: const Duration(milliseconds: 5000),
              receiveTimeout: const Duration(milliseconds: 3000),
            )) {
    if (interceptors == null) {
      this.dio.interceptors.addAll([
        OAuthInterceptor(),
        BasicAuthInterceptor(),
        BearerAuthInterceptor(),
        ApiKeyAuthInterceptor(),
      ]);
    } else {
      this.dio.interceptors.addAll(interceptors);
    }
  }

  void setOAuthToken(String name, String token) {
    if (this.dio.interceptors.any((i) => i is OAuthInterceptor)) {
      (this.dio.interceptors.firstWhere((i) => i is OAuthInterceptor) as OAuthInterceptor).tokens[name] = token;
    }
  }

  void setBearerAuth(String name, String token) {
    if (this.dio.interceptors.any((i) => i is BearerAuthInterceptor)) {
      (this.dio.interceptors.firstWhere((i) => i is BearerAuthInterceptor) as BearerAuthInterceptor).tokens[name] = token;
    }
  }

  void setBasicAuth(String name, String username, String password) {
    if (this.dio.interceptors.any((i) => i is BasicAuthInterceptor)) {
      (this.dio.interceptors.firstWhere((i) => i is BasicAuthInterceptor) as BasicAuthInterceptor).authInfo[name] = BasicAuthInfo(username, password);
    }
  }

  void setApiKey(String name, String apiKey) {
    if (this.dio.interceptors.any((i) => i is ApiKeyAuthInterceptor)) {
      (this.dio.interceptors.firstWhere((element) => element is ApiKeyAuthInterceptor) as ApiKeyAuthInterceptor).apiKeys[name] = apiKey;
    }
  }

  /// Get BroadcastApi instance, base route and serializer can be overridden by a given but be careful,
  /// by doing that all interceptors will not be executed
  BroadcastApi getBroadcastApi() {
    return BroadcastApi(dio, serializers);
  }

  /// Get FCMTokensApi instance, base route and serializer can be overridden by a given but be careful,
  /// by doing that all interceptors will not be executed
  FCMTokensApi getFCMTokensApi() {
    return FCMTokensApi(dio, serializers);
  }

  /// Get InternalApi instance, base route and serializer can be overridden by a given but be careful,
  /// by doing that all interceptors will not be executed
  InternalApi getInternalApi() {
    return InternalApi(dio, serializers);
  }

  /// Get NotificationsApi instance, base route and serializer can be overridden by a given but be careful,
  /// by doing that all interceptors will not be executed
  NotificationsApi getNotificationsApi() {
    return NotificationsApi(dio, serializers);
  }
}
