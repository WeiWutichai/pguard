//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_identity_api/src/model/api_response_envelope.dart';
import 'package:pguard_identity_api/src/model/register_result.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'register202_response.g.dart';

/// Register202Response
///
/// Properties:
/// * [success] 
/// * [error] 
/// * [data] 
@BuiltValue()
abstract class Register202Response implements ApiResponseEnvelope, Built<Register202Response, Register202ResponseBuilder> {
  @BuiltValueField(wireName: r'data')
  RegisterResult? get data;

  Register202Response._();

  factory Register202Response([void updates(Register202ResponseBuilder b)]) = _$Register202Response;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(Register202ResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<Register202Response> get serializer => _$Register202ResponseSerializer();
}

class _$Register202ResponseSerializer implements PrimitiveSerializer<Register202Response> {
  @override
  final Iterable<Type> types = const [Register202Response, _$Register202Response];

  @override
  final String wireName = r'Register202Response';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    Register202Response object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.data != null) {
      yield r'data';
      yield serializers.serialize(
        object.data,
        specifiedType: const FullType(RegisterResult),
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
    Register202Response object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required Register202ResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(RegisterResult),
          ) as RegisterResult;
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
  Register202Response deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = Register202ResponseBuilder();
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

