//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'online_guard.g.dart';

/// One live guard — the id plus the latest fix coordinates (for the nearest-first sort).
///
/// Properties:
/// * [guardId] 
/// * [lat] 
/// * [lng] 
@BuiltValue()
abstract class OnlineGuard implements Built<OnlineGuard, OnlineGuardBuilder> {
  @BuiltValueField(wireName: r'guard_id')
  String get guardId;

  @BuiltValueField(wireName: r'lat')
  double get lat;

  @BuiltValueField(wireName: r'lng')
  double get lng;

  OnlineGuard._();

  factory OnlineGuard([void updates(OnlineGuardBuilder b)]) = _$OnlineGuard;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(OnlineGuardBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<OnlineGuard> get serializer => _$OnlineGuardSerializer();
}

class _$OnlineGuardSerializer implements PrimitiveSerializer<OnlineGuard> {
  @override
  final Iterable<Type> types = const [OnlineGuard, _$OnlineGuard];

  @override
  final String wireName = r'OnlineGuard';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    OnlineGuard object, {
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
  }

  @override
  Object serialize(
    Serializers serializers,
    OnlineGuard object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required OnlineGuardBuilder result,
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
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  OnlineGuard deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = OnlineGuardBuilder();
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

