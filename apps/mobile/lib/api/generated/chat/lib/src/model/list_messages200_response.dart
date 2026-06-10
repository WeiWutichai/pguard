//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:pguard_chat_api/src/model/message.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'list_messages200_response.g.dart';

/// ListMessages200Response
///
/// Properties:
/// * [success] 
/// * [data] 
@BuiltValue()
abstract class ListMessages200Response implements Built<ListMessages200Response, ListMessages200ResponseBuilder> {
  @BuiltValueField(wireName: r'success')
  bool? get success;

  @BuiltValueField(wireName: r'data')
  BuiltList<Message>? get data;

  ListMessages200Response._();

  factory ListMessages200Response([void updates(ListMessages200ResponseBuilder b)]) = _$ListMessages200Response;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ListMessages200ResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ListMessages200Response> get serializer => _$ListMessages200ResponseSerializer();
}

class _$ListMessages200ResponseSerializer implements PrimitiveSerializer<ListMessages200Response> {
  @override
  final Iterable<Type> types = const [ListMessages200Response, _$ListMessages200Response];

  @override
  final String wireName = r'ListMessages200Response';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ListMessages200Response object, {
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
        specifiedType: const FullType(BuiltList, [FullType(Message)]),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    ListMessages200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ListMessages200ResponseBuilder result,
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
            specifiedType: const FullType(BuiltList, [FullType(Message)]),
          ) as BuiltList<Message>;
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
  ListMessages200Response deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ListMessages200ResponseBuilder();
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

