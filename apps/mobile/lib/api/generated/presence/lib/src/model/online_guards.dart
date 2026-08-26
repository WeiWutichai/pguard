//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:pguard_presence_api/src/model/online_guard.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'online_guards.g.dart';

/// OnlineGuards
///
/// Properties:
/// * [guards] - Guards currently OFFERABLE for discovery (is_online alone, NOT freshness-gated), each with their latest fix position.
@BuiltValue()
abstract class OnlineGuards implements Built<OnlineGuards, OnlineGuardsBuilder> {
  /// Guards currently OFFERABLE for discovery (is_online alone, NOT freshness-gated), each with their latest fix position.
  @BuiltValueField(wireName: r'guards')
  BuiltList<OnlineGuard> get guards;

  OnlineGuards._();

  factory OnlineGuards([void updates(OnlineGuardsBuilder b)]) = _$OnlineGuards;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(OnlineGuardsBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<OnlineGuards> get serializer => _$OnlineGuardsSerializer();
}

class _$OnlineGuardsSerializer implements PrimitiveSerializer<OnlineGuards> {
  @override
  final Iterable<Type> types = const [OnlineGuards, _$OnlineGuards];

  @override
  final String wireName = r'OnlineGuards';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    OnlineGuards object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'guards';
    yield serializers.serialize(
      object.guards,
      specifiedType: const FullType(BuiltList, [FullType(OnlineGuard)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    OnlineGuards object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required OnlineGuardsBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'guards':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(OnlineGuard)]),
          ) as BuiltList<OnlineGuard>;
          result.guards.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  OnlineGuards deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = OnlineGuardsBuilder();
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

