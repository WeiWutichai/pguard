//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'admin_call_event.g.dart';

/// A parsed call-summary `system` message — the structured form of the pinned call JSON so the web renders a real call event instead of raw JSON.
///
/// Properties:
/// * [callType] 
/// * [outcome] 
/// * [durationSeconds] - Whole seconds for an answered call; null otherwise.
@BuiltValue()
abstract class AdminCallEvent implements Built<AdminCallEvent, AdminCallEventBuilder> {
  @BuiltValueField(wireName: r'call_type')
  AdminCallEventCallTypeEnum get callType;
  // enum callTypeEnum {  audio,  video,  };

  @BuiltValueField(wireName: r'outcome')
  AdminCallEventOutcomeEnum get outcome;
  // enum outcomeEnum {  completed,  missed,  rejected,  };

  /// Whole seconds for an answered call; null otherwise.
  @BuiltValueField(wireName: r'duration_seconds')
  int? get durationSeconds;

  AdminCallEvent._();

  factory AdminCallEvent([void updates(AdminCallEventBuilder b)]) = _$AdminCallEvent;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AdminCallEventBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AdminCallEvent> get serializer => _$AdminCallEventSerializer();
}

class _$AdminCallEventSerializer implements PrimitiveSerializer<AdminCallEvent> {
  @override
  final Iterable<Type> types = const [AdminCallEvent, _$AdminCallEvent];

  @override
  final String wireName = r'AdminCallEvent';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AdminCallEvent object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'call_type';
    yield serializers.serialize(
      object.callType,
      specifiedType: const FullType(AdminCallEventCallTypeEnum),
    );
    yield r'outcome';
    yield serializers.serialize(
      object.outcome,
      specifiedType: const FullType(AdminCallEventOutcomeEnum),
    );
    if (object.durationSeconds != null) {
      yield r'duration_seconds';
      yield serializers.serialize(
        object.durationSeconds,
        specifiedType: const FullType(int),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    AdminCallEvent object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required AdminCallEventBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'call_type':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(AdminCallEventCallTypeEnum),
          ) as AdminCallEventCallTypeEnum;
          result.callType = valueDes;
          break;
        case r'outcome':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(AdminCallEventOutcomeEnum),
          ) as AdminCallEventOutcomeEnum;
          result.outcome = valueDes;
          break;
        case r'duration_seconds':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.durationSeconds = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  AdminCallEvent deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AdminCallEventBuilder();
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

class AdminCallEventCallTypeEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'audio')
  static const AdminCallEventCallTypeEnum audio = _$adminCallEventCallTypeEnum_audio;
  @BuiltValueEnumConst(wireName: r'video')
  static const AdminCallEventCallTypeEnum video = _$adminCallEventCallTypeEnum_video;

  static Serializer<AdminCallEventCallTypeEnum> get serializer => _$adminCallEventCallTypeEnumSerializer;

  const AdminCallEventCallTypeEnum._(String name): super(name);

  static BuiltSet<AdminCallEventCallTypeEnum> get values => _$adminCallEventCallTypeEnumValues;
  static AdminCallEventCallTypeEnum valueOf(String name) => _$adminCallEventCallTypeEnumValueOf(name);
}

class AdminCallEventOutcomeEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'completed')
  static const AdminCallEventOutcomeEnum completed = _$adminCallEventOutcomeEnum_completed;
  @BuiltValueEnumConst(wireName: r'missed')
  static const AdminCallEventOutcomeEnum missed = _$adminCallEventOutcomeEnum_missed;
  @BuiltValueEnumConst(wireName: r'rejected')
  static const AdminCallEventOutcomeEnum rejected = _$adminCallEventOutcomeEnum_rejected;

  static Serializer<AdminCallEventOutcomeEnum> get serializer => _$adminCallEventOutcomeEnumSerializer;

  const AdminCallEventOutcomeEnum._(String name): super(name);

  static BuiltSet<AdminCallEventOutcomeEnum> get values => _$adminCallEventOutcomeEnumValues;
  static AdminCallEventOutcomeEnum valueOf(String name) => _$adminCallEventOutcomeEnumValueOf(name);
}

