//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_payment_api/src/model/wht_payee_report.dart';
import 'package:pguard_payment_api/src/model/api_response_envelope.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'wht_payee_report200_response.g.dart';

/// WhtPayeeReport200Response
///
/// Properties:
/// * [success] 
/// * [error] 
/// * [data] 
@BuiltValue()
abstract class WhtPayeeReport200Response implements ApiResponseEnvelope, Built<WhtPayeeReport200Response, WhtPayeeReport200ResponseBuilder> {
  @BuiltValueField(wireName: r'data')
  WhtPayeeReport? get data;

  WhtPayeeReport200Response._();

  factory WhtPayeeReport200Response([void updates(WhtPayeeReport200ResponseBuilder b)]) = _$WhtPayeeReport200Response;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(WhtPayeeReport200ResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<WhtPayeeReport200Response> get serializer => _$WhtPayeeReport200ResponseSerializer();
}

class _$WhtPayeeReport200ResponseSerializer implements PrimitiveSerializer<WhtPayeeReport200Response> {
  @override
  final Iterable<Type> types = const [WhtPayeeReport200Response, _$WhtPayeeReport200Response];

  @override
  final String wireName = r'WhtPayeeReport200Response';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    WhtPayeeReport200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.data != null) {
      yield r'data';
      yield serializers.serialize(
        object.data,
        specifiedType: const FullType(WhtPayeeReport),
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
    WhtPayeeReport200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required WhtPayeeReport200ResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(WhtPayeeReport),
          ) as WhtPayeeReport;
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
  WhtPayeeReport200Response deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = WhtPayeeReport200ResponseBuilder();
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

