//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'guard_location.g.dart';

/// GuardLocation
///
/// Properties:
/// * [guardId] 
/// * [lat] 
/// * [lng] 
/// * [accuracy] - Metres.
/// * [heading] - Degrees
/// * [speed] - m/s.
/// * [recordedAt] 
/// * [isOnline] - A live WS session is currently connected.
/// * [isLive] - Discovery freshness — `is_online AND recorded_at` within the last 5 minutes.
@BuiltValue()
abstract class GuardLocation implements Built<GuardLocation, GuardLocationBuilder> {
  @BuiltValueField(wireName: r'guard_id')
  String get guardId;

  @BuiltValueField(wireName: r'lat')
  double get lat;

  @BuiltValueField(wireName: r'lng')
  double get lng;

  /// Metres.
  @BuiltValueField(wireName: r'accuracy')
  double? get accuracy;

  /// Degrees
  @BuiltValueField(wireName: r'heading')
  double? get heading;

  /// m/s.
  @BuiltValueField(wireName: r'speed')
  double? get speed;

  @BuiltValueField(wireName: r'recorded_at')
  DateTime get recordedAt;

  /// A live WS session is currently connected.
  @BuiltValueField(wireName: r'is_online')
  bool get isOnline;

  /// Discovery freshness — `is_online AND recorded_at` within the last 5 minutes.
  @BuiltValueField(wireName: r'is_live')
  bool get isLive;

  GuardLocation._();

  factory GuardLocation([void updates(GuardLocationBuilder b)]) = _$GuardLocation;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(GuardLocationBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<GuardLocation> get serializer => _$GuardLocationSerializer();
}

class _$GuardLocationSerializer implements PrimitiveSerializer<GuardLocation> {
  @override
  final Iterable<Type> types = const [GuardLocation, _$GuardLocation];

  @override
  final String wireName = r'GuardLocation';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    GuardLocation object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'guard_id';
    yield serializers.serialize(
      object.guardId,
      specifiedType: const FullType(String),
    );
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
    if (object.heading != null) {
      yield r'heading';
      yield serializers.serialize(
        object.heading,
        specifiedType: const FullType(double),
      );
    }
    if (object.speed != null) {
      yield r'speed';
      yield serializers.serialize(
        object.speed,
        specifiedType: const FullType(double),
      );
    }
    yield r'recorded_at';
    yield serializers.serialize(
      object.recordedAt,
      specifiedType: const FullType(DateTime),
    );
    yield r'is_online';
    yield serializers.serialize(
      object.isOnline,
      specifiedType: const FullType(bool),
    );
    yield r'is_live';
    yield serializers.serialize(
      object.isLive,
      specifiedType: const FullType(bool),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    GuardLocation object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required GuardLocationBuilder result,
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
        case r'heading':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(double),
          ) as double;
          result.heading = valueDes;
          break;
        case r'speed':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(double),
          ) as double;
          result.speed = valueDes;
          break;
        case r'recorded_at':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.recordedAt = valueDes;
          break;
        case r'is_online':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.isOnline = valueDes;
          break;
        case r'is_live':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.isLive = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  GuardLocation deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = GuardLocationBuilder();
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

