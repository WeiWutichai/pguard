//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_calling_api/src/model/call_event.dart';
import 'package:built_collection/built_collection.dart';
import 'package:pguard_calling_api/src/model/call.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'call_timeline.g.dart';

/// One call's record + its ordered lifecycle timeline. Media QUALITY (jitter/loss/bitrate) is intentionally absent — a signaling relay can't observe it (needs SFU/TURN stats). 
///
/// Properties:
/// * [call] 
/// * [events] - Lifecycle + signaling steps in chronological order.
@BuiltValue()
abstract class CallTimeline implements Built<CallTimeline, CallTimelineBuilder> {
  @BuiltValueField(wireName: r'call')
  Call get call;

  /// Lifecycle + signaling steps in chronological order.
  @BuiltValueField(wireName: r'events')
  BuiltList<CallEvent> get events;

  CallTimeline._();

  factory CallTimeline([void updates(CallTimelineBuilder b)]) = _$CallTimeline;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CallTimelineBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<CallTimeline> get serializer => _$CallTimelineSerializer();
}

class _$CallTimelineSerializer implements PrimitiveSerializer<CallTimeline> {
  @override
  final Iterable<Type> types = const [CallTimeline, _$CallTimeline];

  @override
  final String wireName = r'CallTimeline';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CallTimeline object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'call';
    yield serializers.serialize(
      object.call,
      specifiedType: const FullType(Call),
    );
    yield r'events';
    yield serializers.serialize(
      object.events,
      specifiedType: const FullType(BuiltList, [FullType(CallEvent)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    CallTimeline object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required CallTimelineBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'call':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(Call),
          ) as Call;
          result.call.replace(valueDes);
          break;
        case r'events':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(CallEvent)]),
          ) as BuiltList<CallEvent>;
          result.events.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  CallTimeline deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CallTimelineBuilder();
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

