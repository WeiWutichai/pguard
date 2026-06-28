//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'create_api_token_request.g.dart';

/// CreateApiTokenRequest
///
/// Properties:
/// * [name] - Human label for the token, e.g. \"CI deploy bot\".
@BuiltValue()
abstract class CreateApiTokenRequest implements Built<CreateApiTokenRequest, CreateApiTokenRequestBuilder> {
  /// Human label for the token, e.g. \"CI deploy bot\".
  @BuiltValueField(wireName: r'name')
  String get name;

  CreateApiTokenRequest._();

  factory CreateApiTokenRequest([void updates(CreateApiTokenRequestBuilder b)]) = _$CreateApiTokenRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CreateApiTokenRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<CreateApiTokenRequest> get serializer => _$CreateApiTokenRequestSerializer();
}

class _$CreateApiTokenRequestSerializer implements PrimitiveSerializer<CreateApiTokenRequest> {
  @override
  final Iterable<Type> types = const [CreateApiTokenRequest, _$CreateApiTokenRequest];

  @override
  final String wireName = r'CreateApiTokenRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CreateApiTokenRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'name';
    yield serializers.serialize(
      object.name,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    CreateApiTokenRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required CreateApiTokenRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.name = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  CreateApiTokenRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CreateApiTokenRequestBuilder();
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

