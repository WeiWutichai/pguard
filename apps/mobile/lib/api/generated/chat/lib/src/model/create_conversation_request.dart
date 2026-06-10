//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:pguard_chat_api/src/model/participant_input.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'create_conversation_request.g.dart';

/// CreateConversationRequest
///
/// Properties:
/// * [requestId] - The booking this conversation belongs to (bare UUID, no cross-service FK).
/// * [requestStatus] - Booking status at creation (e.g. `accepted`). Stored to drive the read-only gate; refreshed via `PUT /internal/conversations/by-request/{request_id}/status`.
/// * [participants] - Conversation participants with booking-derived role + optional display data. This supersedes v1's bare `participant_ids[]`: v2 forbids the cross-schema JOIN v1 used to resolve roles/names, so the creator (booking) supplies them inline.
@BuiltValue()
abstract class CreateConversationRequest implements Built<CreateConversationRequest, CreateConversationRequestBuilder> {
  /// The booking this conversation belongs to (bare UUID, no cross-service FK).
  @BuiltValueField(wireName: r'request_id')
  String get requestId;

  /// Booking status at creation (e.g. `accepted`). Stored to drive the read-only gate; refreshed via `PUT /internal/conversations/by-request/{request_id}/status`.
  @BuiltValueField(wireName: r'request_status')
  String? get requestStatus;

  /// Conversation participants with booking-derived role + optional display data. This supersedes v1's bare `participant_ids[]`: v2 forbids the cross-schema JOIN v1 used to resolve roles/names, so the creator (booking) supplies them inline.
  @BuiltValueField(wireName: r'participants')
  BuiltList<ParticipantInput> get participants;

  CreateConversationRequest._();

  factory CreateConversationRequest([void updates(CreateConversationRequestBuilder b)]) = _$CreateConversationRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CreateConversationRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<CreateConversationRequest> get serializer => _$CreateConversationRequestSerializer();
}

class _$CreateConversationRequestSerializer implements PrimitiveSerializer<CreateConversationRequest> {
  @override
  final Iterable<Type> types = const [CreateConversationRequest, _$CreateConversationRequest];

  @override
  final String wireName = r'CreateConversationRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CreateConversationRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'request_id';
    yield serializers.serialize(
      object.requestId,
      specifiedType: const FullType(String),
    );
    if (object.requestStatus != null) {
      yield r'request_status';
      yield serializers.serialize(
        object.requestStatus,
        specifiedType: const FullType(String),
      );
    }
    yield r'participants';
    yield serializers.serialize(
      object.participants,
      specifiedType: const FullType(BuiltList, [FullType(ParticipantInput)]),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    CreateConversationRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required CreateConversationRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'request_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.requestId = valueDes;
          break;
        case r'request_status':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.requestStatus = valueDes;
          break;
        case r'participants':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(ParticipantInput)]),
          ) as BuiltList<ParticipantInput>;
          result.participants.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  CreateConversationRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CreateConversationRequestBuilder();
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

