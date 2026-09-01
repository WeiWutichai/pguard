//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_payment_api/src/model/payout_preview.dart';
import 'package:pguard_payment_api/src/model/api_response_envelope.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'preview_payout200_response.g.dart';

/// PreviewPayout200Response
///
/// Properties:
/// * [success] 
/// * [error] 
/// * [data] 
@BuiltValue()
abstract class PreviewPayout200Response implements ApiResponseEnvelope, Built<PreviewPayout200Response, PreviewPayout200ResponseBuilder> {
  @BuiltValueField(wireName: r'data')
  PayoutPreview? get data;

  PreviewPayout200Response._();

  factory PreviewPayout200Response([void updates(PreviewPayout200ResponseBuilder b)]) = _$PreviewPayout200Response;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PreviewPayout200ResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PreviewPayout200Response> get serializer => _$PreviewPayout200ResponseSerializer();
}

class _$PreviewPayout200ResponseSerializer implements PrimitiveSerializer<PreviewPayout200Response> {
  @override
  final Iterable<Type> types = const [PreviewPayout200Response, _$PreviewPayout200Response];

  @override
  final String wireName = r'PreviewPayout200Response';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PreviewPayout200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.data != null) {
      yield r'data';
      yield serializers.serialize(
        object.data,
        specifiedType: const FullType(PayoutPreview),
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
    PreviewPayout200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PreviewPayout200ResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(PayoutPreview),
          ) as PayoutPreview;
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
  PreviewPayout200Response deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PreviewPayout200ResponseBuilder();
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

