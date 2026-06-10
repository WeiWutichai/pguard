//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:pguard_chat_api/src/model/enriched_conversation.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'list_conversations200_response.g.dart';

/// ListConversations200Response
///
/// Properties:
/// * [success] 
/// * [data] 
@BuiltValue()
abstract class ListConversations200Response implements Built<ListConversations200Response, ListConversations200ResponseBuilder> {
  @BuiltValueField(wireName: r'success')
  bool? get success;

  @BuiltValueField(wireName: r'data')
  BuiltList<EnrichedConversation>? get data;

  ListConversations200Response._();

  factory ListConversations200Response([void updates(ListConversations200ResponseBuilder b)]) = _$ListConversations200Response;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ListConversations200ResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ListConversations200Response> get serializer => _$ListConversations200ResponseSerializer();
}

class _$ListConversations200ResponseSerializer implements PrimitiveSerializer<ListConversations200Response> {
  @override
  final Iterable<Type> types = const [ListConversations200Response, _$ListConversations200Response];

  @override
  final String wireName = r'ListConversations200Response';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ListConversations200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.success != null) {
      yield r'success';
      yield serializers.serialize(
        object.success,
        specifiedType: const FullType(bool),
      );
    }
    if (object.data != null) {
      yield r'data';
      yield serializers.serialize(
        object.data,
        specifiedType: const FullType(BuiltList, [FullType(EnrichedConversation)]),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    ListConversations200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ListConversations200ResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'success':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.success = valueDes;
          break;
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(EnrichedConversation)]),
          ) as BuiltList<EnrichedConversation>;
          result.data.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ListConversations200Response deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ListConversations200ResponseBuilder();
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

