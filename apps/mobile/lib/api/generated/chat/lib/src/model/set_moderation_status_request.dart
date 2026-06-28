//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'set_moderation_status_request.g.dart';

/// Body for the admin set-moderation-status (archive/reactivate) endpoint.
///
/// Properties:
/// * [moderationStatus] - The MODERATION status (distinct from `request_status`). `archived` freezes the thread to new writes; `active` reopens it.
/// * [reason] - Optional audited reason recorded in `chat.moderation_actions`.
@BuiltValue()
abstract class SetModerationStatusRequest implements Built<SetModerationStatusRequest, SetModerationStatusRequestBuilder> {
  /// The MODERATION status (distinct from `request_status`). `archived` freezes the thread to new writes; `active` reopens it.
  @BuiltValueField(wireName: r'moderation_status')
  SetModerationStatusRequestModerationStatusEnum get moderationStatus;
  // enum moderationStatusEnum {  active,  archived,  };

  /// Optional audited reason recorded in `chat.moderation_actions`.
  @BuiltValueField(wireName: r'reason')
  String? get reason;

  SetModerationStatusRequest._();

  factory SetModerationStatusRequest([void updates(SetModerationStatusRequestBuilder b)]) = _$SetModerationStatusRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SetModerationStatusRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SetModerationStatusRequest> get serializer => _$SetModerationStatusRequestSerializer();
}

class _$SetModerationStatusRequestSerializer implements PrimitiveSerializer<SetModerationStatusRequest> {
  @override
  final Iterable<Type> types = const [SetModerationStatusRequest, _$SetModerationStatusRequest];

  @override
  final String wireName = r'SetModerationStatusRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SetModerationStatusRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'moderation_status';
    yield serializers.serialize(
      object.moderationStatus,
      specifiedType: const FullType(SetModerationStatusRequestModerationStatusEnum),
    );
    if (object.reason != null) {
      yield r'reason';
      yield serializers.serialize(
        object.reason,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    SetModerationStatusRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required SetModerationStatusRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'moderation_status':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(SetModerationStatusRequestModerationStatusEnum),
          ) as SetModerationStatusRequestModerationStatusEnum;
          result.moderationStatus = valueDes;
          break;
        case r'reason':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.reason = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  SetModerationStatusRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SetModerationStatusRequestBuilder();
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

class SetModerationStatusRequestModerationStatusEnum extends EnumClass {

  /// The MODERATION status (distinct from `request_status`). `archived` freezes the thread to new writes; `active` reopens it.
  @BuiltValueEnumConst(wireName: r'active')
  static const SetModerationStatusRequestModerationStatusEnum active = _$setModerationStatusRequestModerationStatusEnum_active;
  /// The MODERATION status (distinct from `request_status`). `archived` freezes the thread to new writes; `active` reopens it.
  @BuiltValueEnumConst(wireName: r'archived')
  static const SetModerationStatusRequestModerationStatusEnum archived = _$setModerationStatusRequestModerationStatusEnum_archived;

  static Serializer<SetModerationStatusRequestModerationStatusEnum> get serializer => _$setModerationStatusRequestModerationStatusEnumSerializer;

  const SetModerationStatusRequestModerationStatusEnum._(String name): super(name);

  static BuiltSet<SetModerationStatusRequestModerationStatusEnum> get values => _$setModerationStatusRequestModerationStatusEnumValues;
  static SetModerationStatusRequestModerationStatusEnum valueOf(String name) => _$setModerationStatusRequestModerationStatusEnumValueOf(name);
}

