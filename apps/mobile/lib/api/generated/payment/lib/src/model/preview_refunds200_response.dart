//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_payment_api/src/model/refund_preview.dart';
import 'package:pguard_payment_api/src/model/api_response_envelope.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'preview_refunds200_response.g.dart';

/// PreviewRefunds200Response
///
/// Properties:
/// * [success] 
/// * [error] 
/// * [data] 
@BuiltValue()
abstract class PreviewRefunds200Response implements ApiResponseEnvelope, Built<PreviewRefunds200Response, PreviewRefunds200ResponseBuilder> {
  @BuiltValueField(wireName: r'data')
  RefundPreview? get data;

  PreviewRefunds200Response._();

  factory PreviewRefunds200Response([void updates(PreviewRefunds200ResponseBuilder b)]) = _$PreviewRefunds200Response;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PreviewRefunds200ResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PreviewRefunds200Response> get serializer => _$PreviewRefunds200ResponseSerializer();
}

class _$PreviewRefunds200ResponseSerializer implements PrimitiveSerializer<PreviewRefunds200Response> {
  @override
  final Iterable<Type> types = const [PreviewRefunds200Response, _$PreviewRefunds200Response];

  @override
  final String wireName = r'PreviewRefunds200Response';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PreviewRefunds200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.data != null) {
      yield r'data';
      yield serializers.serialize(
        object.data,
        specifiedType: const FullType(RefundPreview),
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
    PreviewRefunds200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PreviewRefunds200ResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(RefundPreview),
          ) as RefundPreview;
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
  PreviewRefunds200Response deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PreviewRefunds200ResponseBuilder();
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

