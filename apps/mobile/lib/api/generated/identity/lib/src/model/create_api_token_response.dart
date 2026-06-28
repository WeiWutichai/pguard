//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'create_api_token_response.g.dart';

/// The created token. `token` is the FULL bearer (`pguard_<prefix>_<secret>`) shown EXACTLY ONCE — store it now; it is not retrievable later. Only the prefix is listed thereafter. 
///
/// Properties:
/// * [id] 
/// * [name] 
/// * [prefix] 
/// * [token] 
@BuiltValue()
abstract class CreateApiTokenResponse implements Built<CreateApiTokenResponse, CreateApiTokenResponseBuilder> {
  @BuiltValueField(wireName: r'id')
  String get id;

  @BuiltValueField(wireName: r'name')
  String get name;

  @BuiltValueField(wireName: r'prefix')
  String get prefix;

  @BuiltValueField(wireName: r'token')
  String get token;

  CreateApiTokenResponse._();

  factory CreateApiTokenResponse([void updates(CreateApiTokenResponseBuilder b)]) = _$CreateApiTokenResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CreateApiTokenResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<CreateApiTokenResponse> get serializer => _$CreateApiTokenResponseSerializer();
}

class _$CreateApiTokenResponseSerializer implements PrimitiveSerializer<CreateApiTokenResponse> {
  @override
  final Iterable<Type> types = const [CreateApiTokenResponse, _$CreateApiTokenResponse];

  @override
  final String wireName = r'CreateApiTokenResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CreateApiTokenResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'id';
    yield serializers.serialize(
      object.id,
      specifiedType: const FullType(String),
    );
    yield r'name';
    yield serializers.serialize(
      object.name,
      specifiedType: const FullType(String),
    );
    yield r'prefix';
    yield serializers.serialize(
      object.prefix,
      specifiedType: const FullType(String),
    );
    yield r'token';
    yield serializers.serialize(
      object.token,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    CreateApiTokenResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required CreateApiTokenResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.id = valueDes;
          break;
        case r'name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.name = valueDes;
          break;
        case r'prefix':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.prefix = valueDes;
          break;
        case r'token':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.token = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  CreateApiTokenResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CreateApiTokenResponseBuilder();
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

