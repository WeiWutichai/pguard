//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'create_support_ticket_request.g.dart';

/// The mobile Help form body (`POST /support/tickets`). `kind` is the toggle (problem = แจ้งปัญหา, feedback = ส่งความคิดเห็น); `message` is the free-text body (non-empty, trimmed, ≤ 2000 chars). The reporter is NOT in the body — it is the authenticated caller. 
///
/// Properties:
/// * [kind] - problem = report an issue; feedback = a suggestion/comment.
/// * [message] - The report body (1–2000 chars; trimmed server-side).
@BuiltValue()
abstract class CreateSupportTicketRequest implements Built<CreateSupportTicketRequest, CreateSupportTicketRequestBuilder> {
  /// problem = report an issue; feedback = a suggestion/comment.
  @BuiltValueField(wireName: r'kind')
  CreateSupportTicketRequestKindEnum get kind;
  // enum kindEnum {  problem,  feedback,  };

  /// The report body (1–2000 chars; trimmed server-side).
  @BuiltValueField(wireName: r'message')
  String get message;

  CreateSupportTicketRequest._();

  factory CreateSupportTicketRequest([void updates(CreateSupportTicketRequestBuilder b)]) = _$CreateSupportTicketRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CreateSupportTicketRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<CreateSupportTicketRequest> get serializer => _$CreateSupportTicketRequestSerializer();
}

class _$CreateSupportTicketRequestSerializer implements PrimitiveSerializer<CreateSupportTicketRequest> {
  @override
  final Iterable<Type> types = const [CreateSupportTicketRequest, _$CreateSupportTicketRequest];

  @override
  final String wireName = r'CreateSupportTicketRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CreateSupportTicketRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'kind';
    yield serializers.serialize(
      object.kind,
      specifiedType: const FullType(CreateSupportTicketRequestKindEnum),
    );
    yield r'message';
    yield serializers.serialize(
      object.message,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    CreateSupportTicketRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required CreateSupportTicketRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'kind':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(CreateSupportTicketRequestKindEnum),
          ) as CreateSupportTicketRequestKindEnum;
          result.kind = valueDes;
          break;
        case r'message':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.message = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  CreateSupportTicketRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CreateSupportTicketRequestBuilder();
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

class CreateSupportTicketRequestKindEnum extends EnumClass {

  /// problem = report an issue; feedback = a suggestion/comment.
  @BuiltValueEnumConst(wireName: r'problem')
  static const CreateSupportTicketRequestKindEnum problem = _$createSupportTicketRequestKindEnum_problem;
  /// problem = report an issue; feedback = a suggestion/comment.
  @BuiltValueEnumConst(wireName: r'feedback')
  static const CreateSupportTicketRequestKindEnum feedback = _$createSupportTicketRequestKindEnum_feedback;

  static Serializer<CreateSupportTicketRequestKindEnum> get serializer => _$createSupportTicketRequestKindEnumSerializer;

  const CreateSupportTicketRequestKindEnum._(String name): super(name);

  static BuiltSet<CreateSupportTicketRequestKindEnum> get values => _$createSupportTicketRequestKindEnumValues;
  static CreateSupportTicketRequestKindEnum valueOf(String name) => _$createSupportTicketRequestKindEnumValueOf(name);
}

