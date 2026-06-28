//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:pguard_calling_api/src/model/call_event_type.dart';
import 'package:built_value/json_object.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'call_event.g.dart';

/// One step of a call's timeline (admin call-events read model).
///
/// Properties:
/// * [id] 
/// * [callId] 
/// * [eventType] 
/// * [actorId] - The participant this step is attributed to (caller/callee), when known.
/// * [detail] - Small structured metadata about the step (e.g. end_reason, the relayed to/delivered). NEVER the raw SDP/ICE blob.
/// * [occurredAt] 
@BuiltValue()
abstract class CallEvent implements Built<CallEvent, CallEventBuilder> {
  @BuiltValueField(wireName: r'id')
  String get id;

  @BuiltValueField(wireName: r'call_id')
  String get callId;

  @BuiltValueField(wireName: r'event_type')
  CallEventType get eventType;
  // enum eventTypeEnum {  ringing,  accepted,  rejected,  connected,  ended,  missed,  offer,  answer,  ice_candidate,  peer_offline,  };

  /// The participant this step is attributed to (caller/callee), when known.
  @BuiltValueField(wireName: r'actor_id')
  String? get actorId;

  /// Small structured metadata about the step (e.g. end_reason, the relayed to/delivered). NEVER the raw SDP/ICE blob.
  @BuiltValueField(wireName: r'detail')
  BuiltMap<String, JsonObject?>? get detail;

  @BuiltValueField(wireName: r'occurred_at')
  DateTime get occurredAt;

  CallEvent._();

  factory CallEvent([void updates(CallEventBuilder b)]) = _$CallEvent;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CallEventBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<CallEvent> get serializer => _$CallEventSerializer();
}

class _$CallEventSerializer implements PrimitiveSerializer<CallEvent> {
  @override
  final Iterable<Type> types = const [CallEvent, _$CallEvent];

  @override
  final String wireName = r'CallEvent';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CallEvent object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'id';
    yield serializers.serialize(
      object.id,
      specifiedType: const FullType(String),
    );
    yield r'call_id';
    yield serializers.serialize(
      object.callId,
      specifiedType: const FullType(String),
    );
    yield r'event_type';
    yield serializers.serialize(
      object.eventType,
      specifiedType: const FullType(CallEventType),
    );
    if (object.actorId != null) {
      yield r'actor_id';
      yield serializers.serialize(
        object.actorId,
        specifiedType: const FullType(String),
      );
    }
    if (object.detail != null) {
      yield r'detail';
      yield serializers.serialize(
        object.detail,
        specifiedType: const FullType(BuiltMap, [FullType(String), FullType.nullable(JsonObject)]),
      );
    }
    yield r'occurred_at';
    yield serializers.serialize(
      object.occurredAt,
      specifiedType: const FullType(DateTime),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    CallEvent object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required CallEventBuilder result,
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
        case r'call_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.callId = valueDes;
          break;
        case r'event_type':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(CallEventType),
          ) as CallEventType;
          result.eventType = valueDes;
          break;
        case r'actor_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.actorId = valueDes;
          break;
        case r'detail':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltMap, [FullType(String), FullType.nullable(JsonObject)]),
          ) as BuiltMap<String, JsonObject?>;
          result.detail.replace(valueDes);
          break;
        case r'occurred_at':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.occurredAt = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  CallEvent deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CallEventBuilder();
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

