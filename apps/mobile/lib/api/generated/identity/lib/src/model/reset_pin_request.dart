//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'reset_pin_request.g.dart';

/// ResetPinRequest
///
/// Properties:
/// * [phoneVerifiedToken] - Single-use JWT from an OTP run bound to `purpose: \"pin_reset\"` (set at `POST /otp/request`, minted at `POST /otp/verify`). Carries the verified phone (the body has NO phone field). A `phone_verify`-purpose (registration) token is rejected. 
/// * [newPinHash] - SHA-256 hex of the NEW PIN (64 hex chars; same shape as register's `pin_hash`).
@BuiltValue()
abstract class ResetPinRequest implements Built<ResetPinRequest, ResetPinRequestBuilder> {
  /// Single-use JWT from an OTP run bound to `purpose: \"pin_reset\"` (set at `POST /otp/request`, minted at `POST /otp/verify`). Carries the verified phone (the body has NO phone field). A `phone_verify`-purpose (registration) token is rejected. 
  @BuiltValueField(wireName: r'phone_verified_token')
  String get phoneVerifiedToken;

  /// SHA-256 hex of the NEW PIN (64 hex chars; same shape as register's `pin_hash`).
  @BuiltValueField(wireName: r'new_pin_hash')
  String get newPinHash;

  ResetPinRequest._();

  factory ResetPinRequest([void updates(ResetPinRequestBuilder b)]) = _$ResetPinRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ResetPinRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ResetPinRequest> get serializer => _$ResetPinRequestSerializer();
}

class _$ResetPinRequestSerializer implements PrimitiveSerializer<ResetPinRequest> {
  @override
  final Iterable<Type> types = const [ResetPinRequest, _$ResetPinRequest];

  @override
  final String wireName = r'ResetPinRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ResetPinRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'phone_verified_token';
    yield serializers.serialize(
      object.phoneVerifiedToken,
      specifiedType: const FullType(String),
    );
    yield r'new_pin_hash';
    yield serializers.serialize(
      object.newPinHash,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    ResetPinRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ResetPinRequestBuilder result,
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
        case r'new_pin_hash':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.newPinHash = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ResetPinRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ResetPinRequestBuilder();
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

