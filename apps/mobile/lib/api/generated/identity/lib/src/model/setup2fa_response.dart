//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'setup2fa_response.g.dart';

/// TOTP enrollment material (2FA NOT yet enabled). `otpauth_uri` is the `otpauth://totp/...` provisioning URI to render as a QR; `secret` is the base32 manual-entry fallback. 
///
/// Properties:
/// * [otpauthUri] 
/// * [secret] 
@BuiltValue()
abstract class Setup2faResponse implements Built<Setup2faResponse, Setup2faResponseBuilder> {
  @BuiltValueField(wireName: r'otpauth_uri')
  String get otpauthUri;

  @BuiltValueField(wireName: r'secret')
  String get secret;

  Setup2faResponse._();

  factory Setup2faResponse([void updates(Setup2faResponseBuilder b)]) = _$Setup2faResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(Setup2faResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<Setup2faResponse> get serializer => _$Setup2faResponseSerializer();
}

class _$Setup2faResponseSerializer implements PrimitiveSerializer<Setup2faResponse> {
  @override
  final Iterable<Type> types = const [Setup2faResponse, _$Setup2faResponse];

  @override
  final String wireName = r'Setup2faResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    Setup2faResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'otpauth_uri';
    yield serializers.serialize(
      object.otpauthUri,
      specifiedType: const FullType(String),
    );
    yield r'secret';
    yield serializers.serialize(
      object.secret,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    Setup2faResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required Setup2faResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'otpauth_uri':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.otpauthUri = valueDes;
          break;
        case r'secret':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.secret = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  Setup2faResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = Setup2faResponseBuilder();
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

