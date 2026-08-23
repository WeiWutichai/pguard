//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'change_phone_request.g.dart';

/// ChangePhoneRequest
///
/// Properties:
/// * [phoneChangeToken] - Single-use JWT from an OTP run bound to `purpose: \"phone_change\"` (set at `POST /otp/request`, minted at `POST /otp/verify`). Carries the verified NEW phone (the body has NO phone field). A `phone_verify` (registration) or `pin_reset` token is rejected (purpose isolation). 
/// * [currentPinHash] - SHA-256 hex of the CURRENT PIN (same shape/value as login's `password`) — the step-up proof. Verified server-side; a wrong value → a generic 401 (no enumeration). 
@BuiltValue()
abstract class ChangePhoneRequest implements Built<ChangePhoneRequest, ChangePhoneRequestBuilder> {
  /// Single-use JWT from an OTP run bound to `purpose: \"phone_change\"` (set at `POST /otp/request`, minted at `POST /otp/verify`). Carries the verified NEW phone (the body has NO phone field). A `phone_verify` (registration) or `pin_reset` token is rejected (purpose isolation). 
  @BuiltValueField(wireName: r'phone_change_token')
  String get phoneChangeToken;

  /// SHA-256 hex of the CURRENT PIN (same shape/value as login's `password`) — the step-up proof. Verified server-side; a wrong value → a generic 401 (no enumeration). 
  @BuiltValueField(wireName: r'current_pin_hash')
  String get currentPinHash;

  ChangePhoneRequest._();

  factory ChangePhoneRequest([void updates(ChangePhoneRequestBuilder b)]) = _$ChangePhoneRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ChangePhoneRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ChangePhoneRequest> get serializer => _$ChangePhoneRequestSerializer();
}

class _$ChangePhoneRequestSerializer implements PrimitiveSerializer<ChangePhoneRequest> {
  @override
  final Iterable<Type> types = const [ChangePhoneRequest, _$ChangePhoneRequest];

  @override
  final String wireName = r'ChangePhoneRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ChangePhoneRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'phone_change_token';
    yield serializers.serialize(
      object.phoneChangeToken,
      specifiedType: const FullType(String),
    );
    yield r'current_pin_hash';
    yield serializers.serialize(
      object.currentPinHash,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    ChangePhoneRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ChangePhoneRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'phone_change_token':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.phoneChangeToken = valueDes;
          break;
        case r'current_pin_hash':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.currentPinHash = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ChangePhoneRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ChangePhoneRequestBuilder();
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

