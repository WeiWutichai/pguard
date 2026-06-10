//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'rating_summary.g.dart';

/// RatingSummary
///
/// Properties:
/// * [guardId] 
/// * [average] 
/// * [count] 
@BuiltValue()
abstract class RatingSummary implements Built<RatingSummary, RatingSummaryBuilder> {
  @BuiltValueField(wireName: r'guard_id')
  String get guardId;

  @BuiltValueField(wireName: r'average')
  String? get average;

  @BuiltValueField(wireName: r'count')
  int get count;

  RatingSummary._();

  factory RatingSummary([void updates(RatingSummaryBuilder b)]) = _$RatingSummary;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(RatingSummaryBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<RatingSummary> get serializer => _$RatingSummarySerializer();
}

class _$RatingSummarySerializer implements PrimitiveSerializer<RatingSummary> {
  @override
  final Iterable<Type> types = const [RatingSummary, _$RatingSummary];

  @override
  final String wireName = r'RatingSummary';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    RatingSummary object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'guard_id';
    yield serializers.serialize(
      object.guardId,
      specifiedType: const FullType(String),
    );
    if (object.average != null) {
      yield r'average';
      yield serializers.serialize(
        object.average,
        specifiedType: const FullType(String),
      );
    }
    yield r'count';
    yield serializers.serialize(
      object.count,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    RatingSummary object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required RatingSummaryBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'guard_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.guardId = valueDes;
          break;
        case r'average':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.average = valueDes;
          break;
        case r'count':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.count = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  RatingSummary deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = RatingSummaryBuilder();
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

