//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'overdue_checkin.g.dart';

/// An active job whose next scheduled hourly check-in is overdue.
///
/// Properties:
/// * [bookingId] 
/// * [guardId] - The assigned guard who owes the check-in.
/// * [customerId] 
/// * [dueAt] - Open time of the oldest owed-but-unfiled hour (overdue-since).
/// * [missedCount] - Owed hours (open time passed) with no check-in filed yet.
@BuiltValue()
abstract class OverdueCheckin implements Built<OverdueCheckin, OverdueCheckinBuilder> {
  @BuiltValueField(wireName: r'booking_id')
  String get bookingId;

  /// The assigned guard who owes the check-in.
  @BuiltValueField(wireName: r'guard_id')
  String get guardId;

  @BuiltValueField(wireName: r'customer_id')
  String get customerId;

  /// Open time of the oldest owed-but-unfiled hour (overdue-since).
  @BuiltValueField(wireName: r'due_at')
  DateTime get dueAt;

  /// Owed hours (open time passed) with no check-in filed yet.
  @BuiltValueField(wireName: r'missed_count')
  int get missedCount;

  OverdueCheckin._();

  factory OverdueCheckin([void updates(OverdueCheckinBuilder b)]) = _$OverdueCheckin;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(OverdueCheckinBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<OverdueCheckin> get serializer => _$OverdueCheckinSerializer();
}

class _$OverdueCheckinSerializer implements PrimitiveSerializer<OverdueCheckin> {
  @override
  final Iterable<Type> types = const [OverdueCheckin, _$OverdueCheckin];

  @override
  final String wireName = r'OverdueCheckin';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    OverdueCheckin object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'booking_id';
    yield serializers.serialize(
      object.bookingId,
      specifiedType: const FullType(String),
    );
    yield r'guard_id';
    yield serializers.serialize(
      object.guardId,
      specifiedType: const FullType(String),
    );
    yield r'customer_id';
    yield serializers.serialize(
      object.customerId,
      specifiedType: const FullType(String),
    );
    yield r'due_at';
    yield serializers.serialize(
      object.dueAt,
      specifiedType: const FullType(DateTime),
    );
    yield r'missed_count';
    yield serializers.serialize(
      object.missedCount,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    OverdueCheckin object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required OverdueCheckinBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'booking_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.bookingId = valueDes;
          break;
        case r'guard_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.guardId = valueDes;
          break;
        case r'customer_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.customerId = valueDes;
          break;
        case r'due_at':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.dueAt = valueDes;
          break;
        case r'missed_count':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.missedCount = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  OverdueCheckin deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = OverdueCheckinBuilder();
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

