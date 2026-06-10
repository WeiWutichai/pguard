//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'delete_me200_response_all_of_data.g.dart';

/// DeleteMe200ResponseAllOfData
///
/// Properties:
/// * [deleted] 
@BuiltValue()
abstract class DeleteMe200ResponseAllOfData implements Built<DeleteMe200ResponseAllOfData, DeleteMe200ResponseAllOfDataBuilder> {
  @BuiltValueField(wireName: r'deleted')
  bool? get deleted;

  DeleteMe200ResponseAllOfData._();

  factory DeleteMe200ResponseAllOfData([void updates(DeleteMe200ResponseAllOfDataBuilder b)]) = _$DeleteMe200ResponseAllOfData;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(DeleteMe200ResponseAllOfDataBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<DeleteMe200ResponseAllOfData> get serializer => _$DeleteMe200ResponseAllOfDataSerializer();
}

class _$DeleteMe200ResponseAllOfDataSerializer implements PrimitiveSerializer<DeleteMe200ResponseAllOfData> {
  @override
  final Iterable<Type> types = const [DeleteMe200ResponseAllOfData, _$DeleteMe200ResponseAllOfData];

  @override
  final String wireName = r'DeleteMe200ResponseAllOfData';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    DeleteMe200ResponseAllOfData object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.deleted != null) {
      yield r'deleted';
      yield serializers.serialize(
        object.deleted,
        specifiedType: const FullType(bool),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    DeleteMe200ResponseAllOfData object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required DeleteMe200ResponseAllOfDataBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'deleted':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.deleted = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  DeleteMe200ResponseAllOfData deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = DeleteMe200ResponseAllOfDataBuilder();
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

