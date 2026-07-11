//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'start_job_request.g.dart';

/// The guard's GPS fix at the moment of pressing start, feeding the 50m start geofence. The whole body is OPTIONAL (older builds send none): no fix on a pinned booking → 409 `GPS_REQUIRED`; on a legacy address-only booking the geofence skips. `lat`/`lng` must come together (400 otherwise). 
///
/// Properties:
/// * [lat] - Guard latitude at start (must be paired with `lng`).
/// * [lng] - Guard longitude at start (must be paired with `lat`).
/// * [accuracyM] - Reported fix accuracy in meters — widens the 50m fence by up to 30m (negative/NaN counts as 0). Junk values are stored as null.
@BuiltValue()
abstract class StartJobRequest implements Built<StartJobRequest, StartJobRequestBuilder> {
  /// Guard latitude at start (must be paired with `lng`).
  @BuiltValueField(wireName: r'lat')
  double? get lat;

  /// Guard longitude at start (must be paired with `lat`).
  @BuiltValueField(wireName: r'lng')
  double? get lng;

  /// Reported fix accuracy in meters — widens the 50m fence by up to 30m (negative/NaN counts as 0). Junk values are stored as null.
  @BuiltValueField(wireName: r'accuracy_m')
  double? get accuracyM;

  StartJobRequest._();

  factory StartJobRequest([void updates(StartJobRequestBuilder b)]) = _$StartJobRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(StartJobRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<StartJobRequest> get serializer => _$StartJobRequestSerializer();
}

class _$StartJobRequestSerializer implements PrimitiveSerializer<StartJobRequest> {
  @override
  final Iterable<Type> types = const [StartJobRequest, _$StartJobRequest];

  @override
  final String wireName = r'StartJobRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    StartJobRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.lat != null) {
      yield r'lat';
      yield serializers.serialize(
        object.lat,
        specifiedType: const FullType(double),
      );
    }
    if (object.lng != null) {
      yield r'lng';
      yield serializers.serialize(
        object.lng,
        specifiedType: const FullType(double),
      );
    }
    if (object.accuracyM != null) {
      yield r'accuracy_m';
      yield serializers.serialize(
        object.accuracyM,
        specifiedType: const FullType(double),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    StartJobRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required StartJobRequestBuilder result,
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
        case r'accuracy_m':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(double),
          ) as double;
          result.accuracyM = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  StartJobRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = StartJobRequestBuilder();
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

