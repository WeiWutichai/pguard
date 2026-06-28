//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'moderation_result.g.dart';

/// The result of a moderation write. `applied` distinguishes a state-changing call from an idempotent no-op (e.g. re-redacting / re-blocking) — both are success (200).
///
/// Properties:
/// * [applied] - True if this call changed state; false on an idempotent repeat.
/// * [status] - The resulting state (e.g. `redacted`, `archived`, `blocked`, `unblocked`).
@BuiltValue()
abstract class ModerationResult implements Built<ModerationResult, ModerationResultBuilder> {
  /// True if this call changed state; false on an idempotent repeat.
  @BuiltValueField(wireName: r'applied')
  bool get applied;

  /// The resulting state (e.g. `redacted`, `archived`, `blocked`, `unblocked`).
  @BuiltValueField(wireName: r'status')
  String get status;

  ModerationResult._();

  factory ModerationResult([void updates(ModerationResultBuilder b)]) = _$ModerationResult;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ModerationResultBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ModerationResult> get serializer => _$ModerationResultSerializer();
}

class _$ModerationResultSerializer implements PrimitiveSerializer<ModerationResult> {
  @override
  final Iterable<Type> types = const [ModerationResult, _$ModerationResult];

  @override
  final String wireName = r'ModerationResult';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ModerationResult object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'applied';
    yield serializers.serialize(
      object.applied,
      specifiedType: const FullType(bool),
    );
    yield r'status';
    yield serializers.serialize(
      object.status,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    ModerationResult object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ModerationResultBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'applied':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.applied = valueDes;
          break;
        case r'status':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.status = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ModerationResult deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ModerationResultBuilder();
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

