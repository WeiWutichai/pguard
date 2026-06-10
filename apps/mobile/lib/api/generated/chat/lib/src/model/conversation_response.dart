//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'conversation_response.g.dart';

/// ConversationResponse
///
/// Properties:
/// * [id] 
/// * [requestId] 
/// * [requestStatus] 
/// * [createdAt] 
@BuiltValue()
abstract class ConversationResponse implements Built<ConversationResponse, ConversationResponseBuilder> {
  @BuiltValueField(wireName: r'id')
  String get id;

  @BuiltValueField(wireName: r'request_id')
  String get requestId;

  @BuiltValueField(wireName: r'request_status')
  String? get requestStatus;

  @BuiltValueField(wireName: r'created_at')
  DateTime get createdAt;

  ConversationResponse._();

  factory ConversationResponse([void updates(ConversationResponseBuilder b)]) = _$ConversationResponse;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ConversationResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ConversationResponse> get serializer => _$ConversationResponseSerializer();
}

class _$ConversationResponseSerializer implements PrimitiveSerializer<ConversationResponse> {
  @override
  final Iterable<Type> types = const [ConversationResponse, _$ConversationResponse];

  @override
  final String wireName = r'ConversationResponse';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ConversationResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'id';
    yield serializers.serialize(
      object.id,
      specifiedType: const FullType(String),
    );
    yield r'request_id';
    yield serializers.serialize(
      object.requestId,
      specifiedType: const FullType(String),
    );
    if (object.requestStatus != null) {
      yield r'request_status';
      yield serializers.serialize(
        object.requestStatus,
        specifiedType: const FullType(String),
      );
    }
    yield r'created_at';
    yield serializers.serialize(
      object.createdAt,
      specifiedType: const FullType(DateTime),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    ConversationResponse object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ConversationResponseBuilder result,
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
        case r'request_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.requestId = valueDes;
          break;
        case r'request_status':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.requestStatus = valueDes;
          break;
        case r'created_at':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.createdAt = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ConversationResponse deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ConversationResponseBuilder();
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

