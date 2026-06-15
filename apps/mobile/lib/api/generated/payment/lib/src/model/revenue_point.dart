//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_payment_api/src/model/date.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'revenue_point.g.dart';

/// RevenuePoint
///
/// Properties:
/// * [date] 
/// * [revenue] - Net revenue that day (exact decimal as a string; money rule). Net of refunds.
/// * [payments] - Completed charges that day.
@BuiltValue()
abstract class RevenuePoint implements Built<RevenuePoint, RevenuePointBuilder> {
  @BuiltValueField(wireName: r'date')
  Date get date;

  /// Net revenue that day (exact decimal as a string; money rule). Net of refunds.
  @BuiltValueField(wireName: r'revenue')
  String get revenue;

  /// Completed charges that day.
  @BuiltValueField(wireName: r'payments')
  int get payments;

  RevenuePoint._();

  factory RevenuePoint([void updates(RevenuePointBuilder b)]) = _$RevenuePoint;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(RevenuePointBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<RevenuePoint> get serializer => _$RevenuePointSerializer();
}

class _$RevenuePointSerializer implements PrimitiveSerializer<RevenuePoint> {
  @override
  final Iterable<Type> types = const [RevenuePoint, _$RevenuePoint];

  @override
  final String wireName = r'RevenuePoint';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    RevenuePoint object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'date';
    yield serializers.serialize(
      object.date,
      specifiedType: const FullType(Date),
    );
    yield r'revenue';
    yield serializers.serialize(
      object.revenue,
      specifiedType: const FullType(String),
    );
    yield r'payments';
    yield serializers.serialize(
      object.payments,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    RevenuePoint object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required RevenuePointBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'date':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(Date),
          ) as Date;
          result.date = valueDes;
          break;
        case r'revenue':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.revenue = valueDes;
          break;
        case r'payments':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.payments = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  RevenuePoint deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = RevenuePointBuilder();
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

