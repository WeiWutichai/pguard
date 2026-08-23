//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'verify_otp_result.g.dart';

/// VerifyOtpResult
///
/// Properties:
/// * [phoneVerifiedToken] - Single-use JWT scoped to the requested purpose — `phone_verify` tokens are exchanged by identity/profile to finish registration; `pin_reset` tokens by `POST /auth/reset-pin` to reset a forgotten PIN; `phone_change` tokens by `PATCH /auth/phone` to change the login phone
/// * [expiresIn] - Token validity in seconds
@BuiltValue()
abstract class VerifyOtpResult implements Built<VerifyOtpResult, VerifyOtpResultBuilder> {
  /// Single-use JWT scoped to the requested purpose — `phone_verify` tokens are exchanged by identity/profile to finish registration; `pin_reset` tokens by `POST /auth/reset-pin` to reset a forgotten PIN; `phone_change` tokens by `PATCH /auth/phone` to change the login phone
  @BuiltValueField(wireName: r'phone_verified_token')
  String get phoneVerifiedToken;

  /// Token validity in seconds
  @BuiltValueField(wireName: r'expires_in')
  int get expiresIn;

  VerifyOtpResult._();

  factory VerifyOtpResult([void updates(VerifyOtpResultBuilder b)]) = _$VerifyOtpResult;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(VerifyOtpResultBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<VerifyOtpResult> get serializer => _$VerifyOtpResultSerializer();
}

class _$VerifyOtpResultSerializer implements PrimitiveSerializer<VerifyOtpResult> {
  @override
  final Iterable<Type> types = const [VerifyOtpResult, _$VerifyOtpResult];

  @override
  final String wireName = r'VerifyOtpResult';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    VerifyOtpResult object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'phone_verified_token';
    yield serializers.serialize(
      object.phoneVerifiedToken,
      specifiedType: const FullType(String),
    );
    yield r'expires_in';
    yield serializers.serialize(
      object.expiresIn,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    VerifyOtpResult object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required VerifyOtpResultBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'phone_verified_token':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.phoneVerifiedToken = valueDes;
          break;
        case r'expires_in':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.expiresIn = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  VerifyOtpResult deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = VerifyOtpResultBuilder();
    final serializedList = (serialized as Iterable<Object?>).toList();
    final unhandled = <Object?>[];
    _deserializeProperties(
      serializers,
      serialized,
      specifiedType: specifiedType,
      serializedList: serializedList,
      unhandled: unhandled,
      result: result,
    );
    return result.build();
  }
}

