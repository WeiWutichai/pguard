//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'update_rule_request.g.dart';

/// All fields optional (COALESCE); the common edit is the enable toggle.
///
/// Properties:
/// * [triggerKey] 
/// * [conditionText] 
/// * [actionKey] 
/// * [isEnabled] 
@BuiltValue()
abstract class UpdateRuleRequest implements Built<UpdateRuleRequest, UpdateRuleRequestBuilder> {
  @BuiltValueField(wireName: r'trigger_key')
  String? get triggerKey;

  @BuiltValueField(wireName: r'condition_text')
  String? get conditionText;

  @BuiltValueField(wireName: r'action_key')
  String? get actionKey;

  @BuiltValueField(wireName: r'is_enabled')
  bool? get isEnabled;

  UpdateRuleRequest._();

  factory UpdateRuleRequest([void updates(UpdateRuleRequestBuilder b)]) = _$UpdateRuleRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(UpdateRuleRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<UpdateRuleRequest> get serializer => _$UpdateRuleRequestSerializer();
}

class _$UpdateRuleRequestSerializer implements PrimitiveSerializer<UpdateRuleRequest> {
  @override
  final Iterable<Type> types = const [UpdateRuleRequest, _$UpdateRuleRequest];

  @override
  final String wireName = r'UpdateRuleRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    UpdateRuleRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.triggerKey != null) {
      yield r'trigger_key';
      yield serializers.serialize(
        object.triggerKey,
        specifiedType: const FullType(String),
      );
    }
    if (object.conditionText != null) {
      yield r'condition_text';
      yield serializers.serialize(
        object.conditionText,
        specifiedType: const FullType(String),
      );
    }
    if (object.actionKey != null) {
      yield r'action_key';
      yield serializers.serialize(
        object.actionKey,
        specifiedType: const FullType(String),
      );
    }
    if (object.isEnabled != null) {
      yield r'is_enabled';
      yield serializers.serialize(
        object.isEnabled,
        specifiedType: const FullType(bool),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    UpdateRuleRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required UpdateRuleRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
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
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  UpdateRuleRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = UpdateRuleRequestBuilder();
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

