//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'avg_approval_time.g.dart';

/// Average guard approval turnaround (mean of `reviewed_at − created_at` over APPROVED guards). `avg_seconds`/`avg_hours` are null (and `sample_size` 0) when none approved yet. 
///
/// Properties:
/// * [avgSeconds] - Mean approval duration in seconds (null when no approvals yet).
/// * [avgHours] - Same value in hours, rounded to 1 decimal (null when no approvals yet).
/// * [sampleSize] - Number of approved guards the average is over.
@BuiltValue()
abstract class AvgApprovalTime implements Built<AvgApprovalTime, AvgApprovalTimeBuilder> {
  /// Mean approval duration in seconds (null when no approvals yet).
  @BuiltValueField(wireName: r'avg_seconds')
  int? get avgSeconds;

  /// Same value in hours, rounded to 1 decimal (null when no approvals yet).
  @BuiltValueField(wireName: r'avg_hours')
  double? get avgHours;

  /// Number of approved guards the average is over.
  @BuiltValueField(wireName: r'sample_size')
  int get sampleSize;

  AvgApprovalTime._();

  factory AvgApprovalTime([void updates(AvgApprovalTimeBuilder b)]) = _$AvgApprovalTime;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AvgApprovalTimeBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AvgApprovalTime> get serializer => _$AvgApprovalTimeSerializer();
}

class _$AvgApprovalTimeSerializer implements PrimitiveSerializer<AvgApprovalTime> {
  @override
  final Iterable<Type> types = const [AvgApprovalTime, _$AvgApprovalTime];

  @override
  final String wireName = r'AvgApprovalTime';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AvgApprovalTime object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.avgSeconds != null) {
      yield r'avg_seconds';
      yield serializers.serialize(
        object.avgSeconds,
        specifiedType: const FullType(int),
      );
    }
    if (object.avgHours != null) {
      yield r'avg_hours';
      yield serializers.serialize(
        object.avgHours,
        specifiedType: const FullType(double),
      );
    }
    yield r'sample_size';
    yield serializers.serialize(
      object.sampleSize,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    AvgApprovalTime object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required AvgApprovalTimeBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'avg_seconds':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.avgSeconds = valueDes;
          break;
        case r'avg_hours':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(double),
          ) as double;
          result.avgHours = valueDes;
          break;
        case r'sample_size':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.sampleSize = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  AvgApprovalTime deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AvgApprovalTimeBuilder();
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

