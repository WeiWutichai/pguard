//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'retention_point.g.dart';

/// RetentionPoint
///
/// Properties:
/// * [week] 
/// * [pct] - % of customers still active at week N (week 0 = 100).
@BuiltValue()
abstract class RetentionPoint implements Built<RetentionPoint, RetentionPointBuilder> {
  @BuiltValueField(wireName: r'week')
  int get week;

  /// % of customers still active at week N (week 0 = 100).
  @BuiltValueField(wireName: r'pct')
  double get pct;

  RetentionPoint._();

  factory RetentionPoint([void updates(RetentionPointBuilder b)]) = _$RetentionPoint;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(RetentionPointBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<RetentionPoint> get serializer => _$RetentionPointSerializer();
}

class _$RetentionPointSerializer implements PrimitiveSerializer<RetentionPoint> {
  @override
  final Iterable<Type> types = const [RetentionPoint, _$RetentionPoint];

  @override
  final String wireName = r'RetentionPoint';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    RetentionPoint object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'week';
    yield serializers.serialize(
      object.week,
      specifiedType: const FullType(int),
    );
    yield r'pct';
    yield serializers.serialize(
      object.pct,
      specifiedType: const FullType(double),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    RetentionPoint object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required RetentionPointBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'week':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.week = valueDes;
          break;
        case r'pct':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(double),
          ) as double;
          result.pct = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  RetentionPoint deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = RetentionPointBuilder();
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

