//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_profile_api/src/model/api_response_envelope.dart';
import 'package:pguard_profile_api/src/model/support_ticket.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'create_support_ticket200_response.g.dart';

/// CreateSupportTicket200Response
///
/// Properties:
/// * [success] 
/// * [error] 
/// * [data] 
@BuiltValue()
abstract class CreateSupportTicket200Response implements ApiResponseEnvelope, Built<CreateSupportTicket200Response, CreateSupportTicket200ResponseBuilder> {
  @BuiltValueField(wireName: r'data')
  SupportTicket? get data;

  CreateSupportTicket200Response._();

  factory CreateSupportTicket200Response([void updates(CreateSupportTicket200ResponseBuilder b)]) = _$CreateSupportTicket200Response;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CreateSupportTicket200ResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<CreateSupportTicket200Response> get serializer => _$CreateSupportTicket200ResponseSerializer();
}

class _$CreateSupportTicket200ResponseSerializer implements PrimitiveSerializer<CreateSupportTicket200Response> {
  @override
  final Iterable<Type> types = const [CreateSupportTicket200Response, _$CreateSupportTicket200Response];

  @override
  final String wireName = r'CreateSupportTicket200Response';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CreateSupportTicket200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.data != null) {
      yield r'data';
      yield serializers.serialize(
        object.data,
        specifiedType: const FullType(SupportTicket),
      );
    }
    if (object.error != null) {
      yield r'error';
      yield serializers.serialize(
        object.error,
        specifiedType: const FullType(String),
      );
    }
    yield r'success';
    yield serializers.serialize(
      object.success,
      specifiedType: const FullType(bool),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    CreateSupportTicket200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required CreateSupportTicket200ResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(SupportTicket),
          ) as SupportTicket;
          result.data.replace(valueDes);
          break;
        case r'error':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.error = valueDes;
          break;
        case r'success':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.success = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  CreateSupportTicket200Response deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CreateSupportTicket200ResponseBuilder();
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

