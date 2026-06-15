//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'create_rule_request.g.dart';

/// CreateRuleRequest
///
/// Properties:
/// * [triggerKey] 
/// * [conditionText] 
/// * [actionKey] 
/// * [isEnabled] 
@BuiltValue()
abstract class CreateRuleRequest implements Built<CreateRuleRequest, CreateRuleRequestBuilder> {
  @BuiltValueField(wireName: r'trigger_key')
  String get triggerKey;

  @BuiltValueField(wireName: r'condition_text')
  String? get conditionText;

  @BuiltValueField(wireName: r'action_key')
  String get actionKey;

  @BuiltValueField(wireName: r'is_enabled')
  bool? get isEnabled;

  CreateRuleRequest._();

  factory CreateRuleRequest([void updates(CreateRuleRequestBuilder b)]) = _$CreateRuleRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CreateRuleRequestBuilder b) => b
      ..isEnabled = true;

  @BuiltValueSerializer(custom: true)
  static Serializer<CreateRuleRequest> get serializer => _$CreateRuleRequestSerializer();
}

class _$CreateRuleRequestSerializer implements PrimitiveSerializer<CreateRuleRequest> {
  @override
  final Iterable<Type> types = const [CreateRuleRequest, _$CreateRuleRequest];

  @override
  final String wireName = r'CreateRuleRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CreateRuleRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
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
    CreateRuleRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required CreateRuleRequestBuilder result,
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
  CreateRuleRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CreateRuleRequestBuilder();
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

