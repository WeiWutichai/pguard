//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'delete_token_request.g.dart';

/// DeleteTokenRequest
///
/// Properties:
/// * [token] 
@BuiltValue()
abstract class DeleteTokenRequest implements Built<DeleteTokenRequest, DeleteTokenRequestBuilder> {
  @BuiltValueField(wireName: r'token')
  String get token;

  DeleteTokenRequest._();

  factory DeleteTokenRequest([void updates(DeleteTokenRequestBuilder b)]) = _$DeleteTokenRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(DeleteTokenRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<DeleteTokenRequest> get serializer => _$DeleteTokenRequestSerializer();
}

class _$DeleteTokenRequestSerializer implements PrimitiveSerializer<DeleteTokenRequest> {
  @override
  final Iterable<Type> types = const [DeleteTokenRequest, _$DeleteTokenRequest];

  @override
  final String wireName = r'DeleteTokenRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    DeleteTokenRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'token';
    yield serializers.serialize(
      object.token,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    DeleteTokenRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required DeleteTokenRequestBuilder result,
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
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  DeleteTokenRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = DeleteTokenRequestBuilder();
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

