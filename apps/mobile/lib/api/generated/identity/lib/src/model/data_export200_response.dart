//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_identity_api/src/model/data_export200_response_all_of_data.dart';
import 'package:pguard_identity_api/src/model/api_response_envelope.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'data_export200_response.g.dart';

/// DataExport200Response
///
/// Properties:
/// * [success] 
/// * [error] 
/// * [data] 
@BuiltValue()
abstract class DataExport200Response implements ApiResponseEnvelope, Built<DataExport200Response, DataExport200ResponseBuilder> {
  @BuiltValueField(wireName: r'data')
  DataExport200ResponseAllOfData? get data;

  DataExport200Response._();

  factory DataExport200Response([void updates(DataExport200ResponseBuilder b)]) = _$DataExport200Response;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(DataExport200ResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<DataExport200Response> get serializer => _$DataExport200ResponseSerializer();
}

class _$DataExport200ResponseSerializer implements PrimitiveSerializer<DataExport200Response> {
  @override
  final Iterable<Type> types = const [DataExport200Response, _$DataExport200Response];

  @override
  final String wireName = r'DataExport200Response';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    DataExport200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.data != null) {
      yield r'data';
      yield serializers.serialize(
        object.data,
        specifiedType: const FullType(DataExport200ResponseAllOfData),
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
    DataExport200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required DataExport200ResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DataExport200ResponseAllOfData),
          ) as DataExport200ResponseAllOfData;
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
  DataExport200Response deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = DataExport200ResponseBuilder();
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

