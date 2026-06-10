//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_calling_api/src/model/call_type.dart';
import 'package:pguard_calling_api/src/model/call_status.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'call.g.dart';

/// Call
///
/// Properties:
/// * [id] 
/// * [callerId] 
/// * [calleeId] 
/// * [bookingId] 
/// * [callType] 
/// * [status] 
/// * [startedAt] 
/// * [answeredAt] 
/// * [endedAt] 
/// * [durationSeconds] 
/// * [endReason] 
/// * [createdAt] 
/// * [updatedAt] 
@BuiltValue()
abstract class Call implements Built<Call, CallBuilder> {
  @BuiltValueField(wireName: r'id')
  String get id;

  @BuiltValueField(wireName: r'caller_id')
  String get callerId;

  @BuiltValueField(wireName: r'callee_id')
  String get calleeId;

  @BuiltValueField(wireName: r'booking_id')
  String get bookingId;

  @BuiltValueField(wireName: r'call_type')
  CallType get callType;
  // enum callTypeEnum {  audio,  video,  };

  @BuiltValueField(wireName: r'status')
  CallStatus get status;
  // enum statusEnum {  initiated,  accepted,  connected,  ended,  rejected,  missed,  };

  @BuiltValueField(wireName: r'started_at')
  DateTime get startedAt;

  @BuiltValueField(wireName: r'answered_at')
  DateTime? get answeredAt;

  @BuiltValueField(wireName: r'ended_at')
  DateTime? get endedAt;

  @BuiltValueField(wireName: r'duration_seconds')
  int? get durationSeconds;

  @BuiltValueField(wireName: r'end_reason')
  String? get endReason;

  @BuiltValueField(wireName: r'created_at')
  DateTime get createdAt;

  @BuiltValueField(wireName: r'updated_at')
  DateTime get updatedAt;

  Call._();

  factory Call([void updates(CallBuilder b)]) = _$Call;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CallBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<Call> get serializer => _$CallSerializer();
}

class _$CallSerializer implements PrimitiveSerializer<Call> {
  @override
  final Iterable<Type> types = const [Call, _$Call];

  @override
  final String wireName = r'Call';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    Call object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'id';
    yield serializers.serialize(
      object.id,
      specifiedType: const FullType(String),
    );
    yield r'caller_id';
    yield serializers.serialize(
      object.callerId,
      specifiedType: const FullType(String),
    );
    yield r'callee_id';
    yield serializers.serialize(
      object.calleeId,
      specifiedType: const FullType(String),
    );
    yield r'booking_id';
    yield serializers.serialize(
      object.bookingId,
      specifiedType: const FullType(String),
    );
    yield r'call_type';
    yield serializers.serialize(
      object.callType,
      specifiedType: const FullType(CallType),
    );
    yield r'status';
    yield serializers.serialize(
      object.status,
      specifiedType: const FullType(CallStatus),
    );
    yield r'started_at';
    yield serializers.serialize(
      object.startedAt,
      specifiedType: const FullType(DateTime),
    );
    if (object.answeredAt != null) {
      yield r'answered_at';
      yield serializers.serialize(
        object.answeredAt,
        specifiedType: const FullType(DateTime),
      );
    }
    if (object.endedAt != null) {
      yield r'ended_at';
      yield serializers.serialize(
        object.endedAt,
        specifiedType: const FullType(DateTime),
      );
    }
    if (object.durationSeconds != null) {
      yield r'duration_seconds';
      yield serializers.serialize(
        object.durationSeconds,
        specifiedType: const FullType(int),
      );
    }
    if (object.endReason != null) {
      yield r'end_reason';
      yield serializers.serialize(
        object.endReason,
        specifiedType: const FullType(String),
      );
    }
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
    Call object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required CallBuilder result,
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
        case r'caller_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.callerId = valueDes;
          break;
        case r'callee_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.calleeId = valueDes;
          break;
        case r'booking_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.bookingId = valueDes;
          break;
        case r'call_type':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(CallType),
          ) as CallType;
          result.callType = valueDes;
          break;
        case r'status':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(CallStatus),
          ) as CallStatus;
          result.status = valueDes;
          break;
        case r'started_at':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.startedAt = valueDes;
          break;
        case r'answered_at':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.answeredAt = valueDes;
          break;
        case r'ended_at':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.endedAt = valueDes;
          break;
        case r'duration_seconds':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.durationSeconds = valueDes;
          break;
        case r'end_reason':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.endReason = valueDes;
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
  Call deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CallBuilder();
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

