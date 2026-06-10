//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'register_token_request.g.dart';

/// RegisterTokenRequest
///
/// Properties:
/// * [token] - FCM device token
/// * [deviceType] 
@BuiltValue()
abstract class RegisterTokenRequest implements Built<RegisterTokenRequest, RegisterTokenRequestBuilder> {
  /// FCM device token
  @BuiltValueField(wireName: r'token')
  String get token;

  @BuiltValueField(wireName: r'device_type')
  RegisterTokenRequestDeviceTypeEnum get deviceType;
  // enum deviceTypeEnum {  ios,  android,  web,  };

  RegisterTokenRequest._();

  factory RegisterTokenRequest([void updates(RegisterTokenRequestBuilder b)]) = _$RegisterTokenRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(RegisterTokenRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<RegisterTokenRequest> get serializer => _$RegisterTokenRequestSerializer();
}

class _$RegisterTokenRequestSerializer implements PrimitiveSerializer<RegisterTokenRequest> {
  @override
  final Iterable<Type> types = const [RegisterTokenRequest, _$RegisterTokenRequest];

  @override
  final String wireName = r'RegisterTokenRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    RegisterTokenRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'token';
    yield serializers.serialize(
      object.token,
      specifiedType: const FullType(String),
    );
    yield r'device_type';
    yield serializers.serialize(
      object.deviceType,
      specifiedType: const FullType(RegisterTokenRequestDeviceTypeEnum),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    RegisterTokenRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required RegisterTokenRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'token':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.token = valueDes;
          break;
        case r'device_type':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(RegisterTokenRequestDeviceTypeEnum),
          ) as RegisterTokenRequestDeviceTypeEnum;
          result.deviceType = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  RegisterTokenRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = RegisterTokenRequestBuilder();
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

class RegisterTokenRequestDeviceTypeEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'ios')
  static const RegisterTokenRequestDeviceTypeEnum ios = _$registerTokenRequestDeviceTypeEnum_ios;
  @BuiltValueEnumConst(wireName: r'android')
  static const RegisterTokenRequestDeviceTypeEnum android = _$registerTokenRequestDeviceTypeEnum_android;
  @BuiltValueEnumConst(wireName: r'web')
  static const RegisterTokenRequestDeviceTypeEnum web = _$registerTokenRequestDeviceTypeEnum_web;

  static Serializer<RegisterTokenRequestDeviceTypeEnum> get serializer => _$registerTokenRequestDeviceTypeEnumSerializer;

  const RegisterTokenRequestDeviceTypeEnum._(String name): super(name);

  static BuiltSet<RegisterTokenRequestDeviceTypeEnum> get values => _$registerTokenRequestDeviceTypeEnumValues;
  static RegisterTokenRequestDeviceTypeEnum valueOf(String name) => _$registerTokenRequestDeviceTypeEnumValueOf(name);
}

