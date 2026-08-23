//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'support_ticket.g.dart';

/// One support ticket — returned to the reporter on create and to an admin in the newest-first list. `user_id` is the reporter (resolved to a display name by the admin name-resolver on the web side). `status` is `open` on creation (no triage workflow yet). 
///
/// Properties:
/// * [id] 
/// * [userId] - The reporter (identity-owned id).
/// * [kind] 
/// * [message] 
/// * [status] - Lifecycle state; `open` on creation.
/// * [createdAt] 
@BuiltValue()
abstract class SupportTicket implements Built<SupportTicket, SupportTicketBuilder> {
  @BuiltValueField(wireName: r'id')
  String get id;

  /// The reporter (identity-owned id).
  @BuiltValueField(wireName: r'user_id')
  String get userId;

  @BuiltValueField(wireName: r'kind')
  SupportTicketKindEnum get kind;
  // enum kindEnum {  problem,  feedback,  };

  @BuiltValueField(wireName: r'message')
  String get message;

  /// Lifecycle state; `open` on creation.
  @BuiltValueField(wireName: r'status')
  String get status;

  @BuiltValueField(wireName: r'created_at')
  DateTime get createdAt;

  SupportTicket._();

  factory SupportTicket([void updates(SupportTicketBuilder b)]) = _$SupportTicket;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(SupportTicketBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<SupportTicket> get serializer => _$SupportTicketSerializer();
}

class _$SupportTicketSerializer implements PrimitiveSerializer<SupportTicket> {
  @override
  final Iterable<Type> types = const [SupportTicket, _$SupportTicket];

  @override
  final String wireName = r'SupportTicket';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    SupportTicket object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'id';
    yield serializers.serialize(
      object.id,
      specifiedType: const FullType(String),
    );
    yield r'user_id';
    yield serializers.serialize(
      object.userId,
      specifiedType: const FullType(String),
    );
    yield r'kind';
    yield serializers.serialize(
      object.kind,
      specifiedType: const FullType(SupportTicketKindEnum),
    );
    yield r'message';
    yield serializers.serialize(
      object.message,
      specifiedType: const FullType(String),
    );
    yield r'status';
    yield serializers.serialize(
      object.status,
      specifiedType: const FullType(String),
    );
    yield r'created_at';
    yield serializers.serialize(
      object.createdAt,
      specifiedType: const FullType(DateTime),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    SupportTicket object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required SupportTicketBuilder result,
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
        case r'user_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.userId = valueDes;
          break;
        case r'kind':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(SupportTicketKindEnum),
          ) as SupportTicketKindEnum;
          result.kind = valueDes;
          break;
        case r'message':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.message = valueDes;
          break;
        case r'status':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.status = valueDes;
          break;
        case r'created_at':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.createdAt = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  SupportTicket deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = SupportTicketBuilder();
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

class SupportTicketKindEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'problem')
  static const SupportTicketKindEnum problem = _$supportTicketKindEnum_problem;
  @BuiltValueEnumConst(wireName: r'feedback')
  static const SupportTicketKindEnum feedback = _$supportTicketKindEnum_feedback;

  static Serializer<SupportTicketKindEnum> get serializer => _$supportTicketKindEnumSerializer;

  const SupportTicketKindEnum._(String name): super(name);

  static BuiltSet<SupportTicketKindEnum> get values => _$supportTicketKindEnumValues;
  static SupportTicketKindEnum valueOf(String name) => _$supportTicketKindEnumValueOf(name);
}

