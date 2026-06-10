//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'data_export200_response_all_of_data_meta.g.dart';

/// DataExport200ResponseAllOfDataMeta
///
/// Properties:
/// * [generatedAt] 
/// * [sections] 
@BuiltValue()
abstract class DataExport200ResponseAllOfDataMeta implements Built<DataExport200ResponseAllOfDataMeta, DataExport200ResponseAllOfDataMetaBuilder> {
  @BuiltValueField(wireName: r'generated_at')
  DateTime? get generatedAt;

  @BuiltValueField(wireName: r'sections')
  BuiltMap<String, DataExport200ResponseAllOfDataMetaSectionsEnum>? get sections;
  // enum sectionsEnum {  ok,  error,  };

  DataExport200ResponseAllOfDataMeta._();

  factory DataExport200ResponseAllOfDataMeta([void updates(DataExport200ResponseAllOfDataMetaBuilder b)]) = _$DataExport200ResponseAllOfDataMeta;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(DataExport200ResponseAllOfDataMetaBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<DataExport200ResponseAllOfDataMeta> get serializer => _$DataExport200ResponseAllOfDataMetaSerializer();
}

class _$DataExport200ResponseAllOfDataMetaSerializer implements PrimitiveSerializer<DataExport200ResponseAllOfDataMeta> {
  @override
  final Iterable<Type> types = const [DataExport200ResponseAllOfDataMeta, _$DataExport200ResponseAllOfDataMeta];

  @override
  final String wireName = r'DataExport200ResponseAllOfDataMeta';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    DataExport200ResponseAllOfDataMeta object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.generatedAt != null) {
      yield r'generated_at';
      yield serializers.serialize(
        object.generatedAt,
        specifiedType: const FullType(DateTime),
      );
    }
    if (object.sections != null) {
      yield r'sections';
      yield serializers.serialize(
        object.sections,
        specifiedType: const FullType(BuiltMap, [FullType(String), FullType(DataExport200ResponseAllOfDataMetaSectionsEnum)]),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    DataExport200ResponseAllOfDataMeta object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required DataExport200ResponseAllOfDataMetaBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'generated_at':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.generatedAt = valueDes;
          break;
        case r'sections':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltMap, [FullType(String), FullType(DataExport200ResponseAllOfDataMetaSectionsEnum)]),
          ) as BuiltMap<String, DataExport200ResponseAllOfDataMetaSectionsEnum>;
          result.sections.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  DataExport200ResponseAllOfDataMeta deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = DataExport200ResponseAllOfDataMetaBuilder();
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

class DataExport200ResponseAllOfDataMetaSectionsEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'ok')
  static const DataExport200ResponseAllOfDataMetaSectionsEnum ok = _$dataExport200ResponseAllOfDataMetaSectionsEnum_ok;
  @BuiltValueEnumConst(wireName: r'error')
  static const DataExport200ResponseAllOfDataMetaSectionsEnum error = _$dataExport200ResponseAllOfDataMetaSectionsEnum_error;

  static Serializer<DataExport200ResponseAllOfDataMetaSectionsEnum> get serializer => _$dataExport200ResponseAllOfDataMetaSectionsEnumSerializer;

  const DataExport200ResponseAllOfDataMetaSectionsEnum._(String name): super(name);

  static BuiltSet<DataExport200ResponseAllOfDataMetaSectionsEnum> get values => _$dataExport200ResponseAllOfDataMetaSectionsEnumValues;
  static DataExport200ResponseAllOfDataMetaSectionsEnum valueOf(String name) => _$dataExport200ResponseAllOfDataMetaSectionsEnumValueOf(name);
}

