//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:pguard_identity_api/src/model/data_export200_response_all_of_data_meta.dart';
import 'package:built_value/json_object.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'data_export200_response_all_of_data.g.dart';

/// `{ user, profile, bookings, payments, reviews, _meta }` where `_meta = { generated_at, sections: { <section>: \"ok\" | \"error\" } }`. 
///
/// Properties:
/// * [user] 
/// * [profile] 
/// * [bookings] 
/// * [payments] 
/// * [reviews] 
/// * [meta] 
@BuiltValue()
abstract class DataExport200ResponseAllOfData implements Built<DataExport200ResponseAllOfData, DataExport200ResponseAllOfDataBuilder> {
  @BuiltValueField(wireName: r'user')
  JsonObject? get user;

  @BuiltValueField(wireName: r'profile')
  JsonObject? get profile;

  @BuiltValueField(wireName: r'bookings')
  BuiltList<JsonObject>? get bookings;

  @BuiltValueField(wireName: r'payments')
  BuiltList<JsonObject>? get payments;

  @BuiltValueField(wireName: r'reviews')
  BuiltList<JsonObject>? get reviews;

  @BuiltValueField(wireName: r'_meta')
  DataExport200ResponseAllOfDataMeta? get meta;

  DataExport200ResponseAllOfData._();

  factory DataExport200ResponseAllOfData([void updates(DataExport200ResponseAllOfDataBuilder b)]) = _$DataExport200ResponseAllOfData;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(DataExport200ResponseAllOfDataBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<DataExport200ResponseAllOfData> get serializer => _$DataExport200ResponseAllOfDataSerializer();
}

class _$DataExport200ResponseAllOfDataSerializer implements PrimitiveSerializer<DataExport200ResponseAllOfData> {
  @override
  final Iterable<Type> types = const [DataExport200ResponseAllOfData, _$DataExport200ResponseAllOfData];

  @override
  final String wireName = r'DataExport200ResponseAllOfData';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    DataExport200ResponseAllOfData object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.user != null) {
      yield r'user';
      yield serializers.serialize(
        object.user,
        specifiedType: const FullType(JsonObject),
      );
    }
    if (object.profile != null) {
      yield r'profile';
      yield serializers.serialize(
        object.profile,
        specifiedType: const FullType(JsonObject),
      );
    }
    if (object.bookings != null) {
      yield r'bookings';
      yield serializers.serialize(
        object.bookings,
        specifiedType: const FullType(BuiltList, [FullType(JsonObject)]),
      );
    }
    if (object.payments != null) {
      yield r'payments';
      yield serializers.serialize(
        object.payments,
        specifiedType: const FullType(BuiltList, [FullType(JsonObject)]),
      );
    }
    if (object.reviews != null) {
      yield r'reviews';
      yield serializers.serialize(
        object.reviews,
        specifiedType: const FullType(BuiltList, [FullType(JsonObject)]),
      );
    }
    if (object.meta != null) {
      yield r'_meta';
      yield serializers.serialize(
        object.meta,
        specifiedType: const FullType(DataExport200ResponseAllOfDataMeta),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    DataExport200ResponseAllOfData object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required DataExport200ResponseAllOfDataBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'user':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(JsonObject),
          ) as JsonObject;
          result.user = valueDes;
          break;
        case r'profile':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(JsonObject),
          ) as JsonObject;
          result.profile = valueDes;
          break;
        case r'bookings':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(JsonObject)]),
          ) as BuiltList<JsonObject>;
          result.bookings.replace(valueDes);
          break;
        case r'payments':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(JsonObject)]),
          ) as BuiltList<JsonObject>;
          result.payments.replace(valueDes);
          break;
        case r'reviews':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(JsonObject)]),
          ) as BuiltList<JsonObject>;
          result.reviews.replace(valueDes);
          break;
        case r'_meta':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DataExport200ResponseAllOfDataMeta),
          ) as DataExport200ResponseAllOfDataMeta;
          result.meta.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  DataExport200ResponseAllOfData deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = DataExport200ResponseAllOfDataBuilder();
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

