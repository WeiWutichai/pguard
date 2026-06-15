//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:pguard_chat_api/src/model/admin_conversation.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'admin_list_conversations200_response.g.dart';

/// AdminListConversations200Response
///
/// Properties:
/// * [success] 
/// * [data] 
@BuiltValue()
abstract class AdminListConversations200Response implements Built<AdminListConversations200Response, AdminListConversations200ResponseBuilder> {
  @BuiltValueField(wireName: r'success')
  bool? get success;

  @BuiltValueField(wireName: r'data')
  BuiltList<AdminConversation>? get data;

  AdminListConversations200Response._();

  factory AdminListConversations200Response([void updates(AdminListConversations200ResponseBuilder b)]) = _$AdminListConversations200Response;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AdminListConversations200ResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AdminListConversations200Response> get serializer => _$AdminListConversations200ResponseSerializer();
}

class _$AdminListConversations200ResponseSerializer implements PrimitiveSerializer<AdminListConversations200Response> {
  @override
  final Iterable<Type> types = const [AdminListConversations200Response, _$AdminListConversations200Response];

  @override
  final String wireName = r'AdminListConversations200Response';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AdminListConversations200Response object, {
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
        specifiedType: const FullType(BuiltList, [FullType(AdminConversation)]),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    AdminListConversations200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required AdminListConversations200ResponseBuilder result,
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
            specifiedType: const FullType(BuiltList, [FullType(AdminConversation)]),
          ) as BuiltList<AdminConversation>;
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
  AdminListConversations200Response deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AdminListConversations200ResponseBuilder();
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

