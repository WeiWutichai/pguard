//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'service_type_stat.g.dart';

/// One row of the bookings-by-service-type report: a catalog service with its booking count + gross revenue in the window. `service_id` / names are null for the \"unspecified\" bucket (bookings placed without a service).
///
/// Properties:
/// * [serviceId] - Catalog service id
/// * [nameTh] - Catalog Thai name (null for the unspecified bucket).
/// * [nameEn] - Catalog English name (null for the unspecified bucket).
/// * [count] - Bookings placed against this service in the window (all statuses).
/// * [revenue] - Gross ฿ revenue (Σ base_fee×hours×guard_count + tip over non-cancelled bookings; exact decimal)
@BuiltValue()
abstract class ServiceTypeStat implements Built<ServiceTypeStat, ServiceTypeStatBuilder> {
  /// Catalog service id
  @BuiltValueField(wireName: r'service_id')
  String? get serviceId;

  /// Catalog Thai name (null for the unspecified bucket).
  @BuiltValueField(wireName: r'name_th')
  String? get nameTh;

  /// Catalog English name (null for the unspecified bucket).
  @BuiltValueField(wireName: r'name_en')
  String? get nameEn;

  /// Bookings placed against this service in the window (all statuses).
  @BuiltValueField(wireName: r'count')
  int get count;

  /// Gross ฿ revenue (Σ base_fee×hours×guard_count + tip over non-cancelled bookings; exact decimal)
  @BuiltValueField(wireName: r'revenue')
  String get revenue;

  ServiceTypeStat._();

  factory ServiceTypeStat([void updates(ServiceTypeStatBuilder b)]) = _$ServiceTypeStat;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ServiceTypeStatBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ServiceTypeStat> get serializer => _$ServiceTypeStatSerializer();
}

class _$ServiceTypeStatSerializer implements PrimitiveSerializer<ServiceTypeStat> {
  @override
  final Iterable<Type> types = const [ServiceTypeStat, _$ServiceTypeStat];

  @override
  final String wireName = r'ServiceTypeStat';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ServiceTypeStat object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.serviceId != null) {
      yield r'service_id';
      yield serializers.serialize(
        object.serviceId,
        specifiedType: const FullType(String),
      );
    }
    if (object.nameTh != null) {
      yield r'name_th';
      yield serializers.serialize(
        object.nameTh,
        specifiedType: const FullType(String),
      );
    }
    if (object.nameEn != null) {
      yield r'name_en';
      yield serializers.serialize(
        object.nameEn,
        specifiedType: const FullType(String),
      );
    }
    yield r'count';
    yield serializers.serialize(
      object.count,
      specifiedType: const FullType(int),
    );
    yield r'revenue';
    yield serializers.serialize(
      object.revenue,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    ServiceTypeStat object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ServiceTypeStatBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'service_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.serviceId = valueDes;
          break;
        case r'name_th':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.nameTh = valueDes;
          break;
        case r'name_en':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.nameEn = valueDes;
          break;
        case r'count':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.count = valueDes;
          break;
        case r'revenue':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.revenue = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ServiceTypeStat deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ServiceTypeStatBuilder();
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

