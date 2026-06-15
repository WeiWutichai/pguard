//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'utilization_cell.g.dart';

/// Guard-hours in a day-of-week × 2-hour slot (`hours` = Σ hours×guard_count).
///
/// Properties:
/// * [dow] - 0=Sunday .. 6=Saturday
/// * [bucket] - 2-hour bucket 0..11 (0 = 00:00–02:00)
/// * [hours] 
@BuiltValue()
abstract class UtilizationCell implements Built<UtilizationCell, UtilizationCellBuilder> {
  /// 0=Sunday .. 6=Saturday
  @BuiltValueField(wireName: r'dow')
  int get dow;

  /// 2-hour bucket 0..11 (0 = 00:00–02:00)
  @BuiltValueField(wireName: r'bucket')
  int get bucket;

  @BuiltValueField(wireName: r'hours')
  int get hours;

  UtilizationCell._();

  factory UtilizationCell([void updates(UtilizationCellBuilder b)]) = _$UtilizationCell;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(UtilizationCellBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<UtilizationCell> get serializer => _$UtilizationCellSerializer();
}

class _$UtilizationCellSerializer implements PrimitiveSerializer<UtilizationCell> {
  @override
  final Iterable<Type> types = const [UtilizationCell, _$UtilizationCell];

  @override
  final String wireName = r'UtilizationCell';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    UtilizationCell object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'dow';
    yield serializers.serialize(
      object.dow,
      specifiedType: const FullType(int),
    );
    yield r'bucket';
    yield serializers.serialize(
      object.bucket,
      specifiedType: const FullType(int),
    );
    yield r'hours';
    yield serializers.serialize(
      object.hours,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    UtilizationCell object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required UtilizationCellBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'dow':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.dow = valueDes;
          break;
        case r'bucket':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.bucket = valueDes;
          break;
        case r'hours':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.hours = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  UtilizationCell deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = UtilizationCellBuilder();
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

