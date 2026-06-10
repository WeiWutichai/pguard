//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'history_point.g.dart';

/// HistoryPoint
///
/// Properties:
/// * [lat] 
/// * [lng] 
/// * [accuracy] 
/// * [recordedAt] 
@BuiltValue()
abstract class HistoryPoint implements Built<HistoryPoint, HistoryPointBuilder> {
  @BuiltValueField(wireName: r'lat')
  double get lat;

  @BuiltValueField(wireName: r'lng')
  double get lng;

  @BuiltValueField(wireName: r'accuracy')
  double? get accuracy;

  @BuiltValueField(wireName: r'recorded_at')
  DateTime get recordedAt;

  HistoryPoint._();

  factory HistoryPoint([void updates(HistoryPointBuilder b)]) = _$HistoryPoint;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(HistoryPointBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<HistoryPoint> get serializer => _$HistoryPointSerializer();
}

class _$HistoryPointSerializer implements PrimitiveSerializer<HistoryPoint> {
  @override
  final Iterable<Type> types = const [HistoryPoint, _$HistoryPoint];

  @override
  final String wireName = r'HistoryPoint';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    HistoryPoint object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'lat';
    yield serializers.serialize(
      object.lat,
      specifiedType: const FullType(double),
    );
    yield r'lng';
    yield serializers.serialize(
      object.lng,
      specifiedType: const FullType(double),
    );
    if (object.accuracy != null) {
      yield r'accuracy';
      yield serializers.serialize(
        object.accuracy,
        specifiedType: const FullType(double),
      );
    }
    yield r'recorded_at';
    yield serializers.serialize(
      object.recordedAt,
      specifiedType: const FullType(DateTime),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    HistoryPoint object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required HistoryPointBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'lat':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(double),
          ) as double;
          result.lat = valueDes;
          break;
        case r'lng':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(double),
          ) as double;
          result.lng = valueDes;
          break;
        case r'accuracy':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(double),
          ) as double;
          result.accuracy = valueDes;
          break;
        case r'recorded_at':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.recordedAt = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  HistoryPoint deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = HistoryPointBuilder();
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

