//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_chat_api/src/model/admin_enriched_message.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'admin_list_messages200_response.g.dart';

/// AdminListMessages200Response
///
/// Properties:
/// * [success] 
/// * [data] 
@BuiltValue()
abstract class AdminListMessages200Response implements Built<AdminListMessages200Response, AdminListMessages200ResponseBuilder> {
  @BuiltValueField(wireName: r'success')
  bool? get success;

  @BuiltValueField(wireName: r'data')
  BuiltList<AdminEnrichedMessage>? get data;

  AdminListMessages200Response._();

  factory AdminListMessages200Response([void updates(AdminListMessages200ResponseBuilder b)]) = _$AdminListMessages200Response;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AdminListMessages200ResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AdminListMessages200Response> get serializer => _$AdminListMessages200ResponseSerializer();
}

class _$AdminListMessages200ResponseSerializer implements PrimitiveSerializer<AdminListMessages200Response> {
  @override
  final Iterable<Type> types = const [AdminListMessages200Response, _$AdminListMessages200Response];

  @override
  final String wireName = r'AdminListMessages200Response';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AdminListMessages200Response object, {
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
        specifiedType: const FullType(BuiltList, [FullType(AdminEnrichedMessage)]),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    AdminListMessages200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required AdminListMessages200ResponseBuilder result,
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
            specifiedType: const FullType(BuiltList, [FullType(AdminEnrichedMessage)]),
          ) as BuiltList<AdminEnrichedMessage>;
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
  AdminListMessages200Response deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AdminListMessages200ResponseBuilder();
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

