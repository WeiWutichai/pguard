//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_otp_api/src/model/error_detail.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'error_body.g.dart';

/// ErrorBody
///
/// Properties:
/// * [error] 
@BuiltValue()
abstract class ErrorBody implements Built<ErrorBody, ErrorBodyBuilder> {
  @BuiltValueField(wireName: r'error')
  ErrorDetail get error;

  ErrorBody._();

  factory ErrorBody([void updates(ErrorBodyBuilder b)]) = _$ErrorBody;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ErrorBodyBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ErrorBody> get serializer => _$ErrorBodySerializer();
}

class _$ErrorBodySerializer implements PrimitiveSerializer<ErrorBody> {
  @override
  final Iterable<Type> types = const [ErrorBody, _$ErrorBody];

  @override
  final String wireName = r'ErrorBody';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ErrorBody object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'error';
    yield serializers.serialize(
      object.error,
      specifiedType: const FullType(ErrorDetail),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    ErrorBody object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ErrorBodyBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'error':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ErrorDetail),
          ) as ErrorDetail;
          result.error.replace(valueDes);
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ErrorBody deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ErrorBodyBuilder();
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

