//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'excluded_guard.g.dart';

/// ExcludedGuard
///
/// Properties:
/// * [guardId] 
/// * [reason] - Thai copy explaining why this guard cannot be paid in this batch — no profile row, no name, no usable PromptPay proxy, no tax id/address for the ภ.ง.ด. certificate, or a total transfer outside SCB's per-transaction bounds (the reason names the bound). The guard's jobs stay unpaid in the backlog; nothing is marked paid. 
/// * [jobCount] 
@BuiltValue()
abstract class ExcludedGuard implements Built<ExcludedGuard, ExcludedGuardBuilder> {
  @BuiltValueField(wireName: r'guard_id')
  String get guardId;

  /// Thai copy explaining why this guard cannot be paid in this batch — no profile row, no name, no usable PromptPay proxy, no tax id/address for the ภ.ง.ด. certificate, or a total transfer outside SCB's per-transaction bounds (the reason names the bound). The guard's jobs stay unpaid in the backlog; nothing is marked paid. 
  @BuiltValueField(wireName: r'reason')
  String get reason;

  @BuiltValueField(wireName: r'job_count')
  int get jobCount;

  ExcludedGuard._();

  factory ExcludedGuard([void updates(ExcludedGuardBuilder b)]) = _$ExcludedGuard;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ExcludedGuardBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ExcludedGuard> get serializer => _$ExcludedGuardSerializer();
}

class _$ExcludedGuardSerializer implements PrimitiveSerializer<ExcludedGuard> {
  @override
  final Iterable<Type> types = const [ExcludedGuard, _$ExcludedGuard];

  @override
  final String wireName = r'ExcludedGuard';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ExcludedGuard object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'guard_id';
    yield serializers.serialize(
      object.guardId,
      specifiedType: const FullType(String),
    );
    yield r'reason';
    yield serializers.serialize(
      object.reason,
      specifiedType: const FullType(String),
    );
    yield r'job_count';
    yield serializers.serialize(
      object.jobCount,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    ExcludedGuard object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ExcludedGuardBuilder result,
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
        case r'reason':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.reason = valueDes;
          break;
        case r'job_count':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.jobCount = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ExcludedGuard deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ExcludedGuardBuilder();
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

