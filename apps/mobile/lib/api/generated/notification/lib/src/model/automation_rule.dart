//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'automation_rule.g.dart';

/// AutomationRule
///
/// Properties:
/// * [id] 
/// * [triggerKey] - When (a fixed admin-facing key set).
/// * [conditionText] 
/// * [actionKey] - Then (a fixed admin-facing key set).
/// * [isEnabled] 
/// * [createdBy] 
/// * [createdAt] 
/// * [updatedAt] 
@BuiltValue()
abstract class AutomationRule implements Built<AutomationRule, AutomationRuleBuilder> {
  @BuiltValueField(wireName: r'id')
  String get id;

  /// When (a fixed admin-facing key set).
  @BuiltValueField(wireName: r'trigger_key')
  String get triggerKey;

  @BuiltValueField(wireName: r'condition_text')
  String? get conditionText;

  /// Then (a fixed admin-facing key set).
  @BuiltValueField(wireName: r'action_key')
  String get actionKey;

  @BuiltValueField(wireName: r'is_enabled')
  bool get isEnabled;

  @BuiltValueField(wireName: r'created_by')
  String get createdBy;

  @BuiltValueField(wireName: r'created_at')
  DateTime get createdAt;

  @BuiltValueField(wireName: r'updated_at')
  DateTime get updatedAt;

  AutomationRule._();

  factory AutomationRule([void updates(AutomationRuleBuilder b)]) = _$AutomationRule;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AutomationRuleBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AutomationRule> get serializer => _$AutomationRuleSerializer();
}

class _$AutomationRuleSerializer implements PrimitiveSerializer<AutomationRule> {
  @override
  final Iterable<Type> types = const [AutomationRule, _$AutomationRule];

  @override
  final String wireName = r'AutomationRule';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AutomationRule object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'id';
    yield serializers.serialize(
      object.id,
      specifiedType: const FullType(String),
    );
    yield r'trigger_key';
    yield serializers.serialize(
      object.triggerKey,
      specifiedType: const FullType(String),
    );
    if (object.conditionText != null) {
      yield r'condition_text';
      yield serializers.serialize(
        object.conditionText,
        specifiedType: const FullType(String),
      );
    }
    yield r'action_key';
    yield serializers.serialize(
      object.actionKey,
      specifiedType: const FullType(String),
    );
    yield r'is_enabled';
    yield serializers.serialize(
      object.isEnabled,
      specifiedType: const FullType(bool),
    );
    yield r'created_by';
    yield serializers.serialize(
      object.createdBy,
      specifiedType: const FullType(String),
    );
    yield r'created_at';
    yield serializers.serialize(
      object.createdAt,
      specifiedType: const FullType(DateTime),
    );
    yield r'updated_at';
    yield serializers.serialize(
      object.updatedAt,
      specifiedType: const FullType(DateTime),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    AutomationRule object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required AutomationRuleBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.id = valueDes;
          break;
        case r'trigger_key':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.triggerKey = valueDes;
          break;
        case r'condition_text':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.conditionText = valueDes;
          break;
        case r'action_key':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.actionKey = valueDes;
          break;
        case r'is_enabled':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.isEnabled = valueDes;
          break;
        case r'created_by':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.createdBy = valueDes;
          break;
        case r'created_at':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.createdAt = valueDes;
          break;
        case r'updated_at':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.updatedAt = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  AutomationRule deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AutomationRuleBuilder();
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

