//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'phone_status_request.g.dart';

/// PhoneStatusRequest
///
/// Properties:
/// * [phoneVerifiedToken] 
@BuiltValue()
abstract class PhoneStatusRequest implements Built<PhoneStatusRequest, PhoneStatusRequestBuilder> {
  @BuiltValueField(wireName: r'phone_verified_token')
  String get phoneVerifiedToken;

  PhoneStatusRequest._();

  factory PhoneStatusRequest([void updates(PhoneStatusRequestBuilder b)]) = _$PhoneStatusRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PhoneStatusRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PhoneStatusRequest> get serializer => _$PhoneStatusRequestSerializer();
}

class _$PhoneStatusRequestSerializer implements PrimitiveSerializer<PhoneStatusRequest> {
  @override
  final Iterable<Type> types = const [PhoneStatusRequest, _$PhoneStatusRequest];

  @override
  final String wireName = r'PhoneStatusRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PhoneStatusRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'phone_verified_token';
    yield serializers.serialize(
      object.phoneVerifiedToken,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    PhoneStatusRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PhoneStatusRequestBuilder result,
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
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  PhoneStatusRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PhoneStatusRequestBuilder();
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

