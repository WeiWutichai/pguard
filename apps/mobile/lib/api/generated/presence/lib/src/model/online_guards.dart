//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'online_guards.g.dart';

/// OnlineGuards
///
/// Properties:
/// * [guardIds] - Ids of guards currently LIVE (is_online AND a fresh fix). Ids only — no PII.
@BuiltValue()
abstract class OnlineGuards implements Built<OnlineGuards, OnlineGuardsBuilder> {
  /// Ids of guards currently LIVE (is_online AND a fresh fix). Ids only — no PII.
  @BuiltValueField(wireName: r'guard_ids')
  BuiltList<String> get guardIds;

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
    yield r'guard_ids';
    yield serializers.serialize(
      object.guardIds,
      specifiedType: const FullType(BuiltList, [FullType(String)]),
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
        case r'guard_ids':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.guardIds.replace(valueDes);
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

