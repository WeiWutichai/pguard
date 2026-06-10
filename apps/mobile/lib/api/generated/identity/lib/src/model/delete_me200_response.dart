//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_identity_api/src/model/delete_me200_response_all_of_data.dart';
import 'package:pguard_identity_api/src/model/api_response_envelope.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'delete_me200_response.g.dart';

/// DeleteMe200Response
///
/// Properties:
/// * [success] 
/// * [error] 
/// * [data] 
@BuiltValue()
abstract class DeleteMe200Response implements ApiResponseEnvelope, Built<DeleteMe200Response, DeleteMe200ResponseBuilder> {
  @BuiltValueField(wireName: r'data')
  DeleteMe200ResponseAllOfData? get data;

  DeleteMe200Response._();

  factory DeleteMe200Response([void updates(DeleteMe200ResponseBuilder b)]) = _$DeleteMe200Response;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(DeleteMe200ResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<DeleteMe200Response> get serializer => _$DeleteMe200ResponseSerializer();
}

class _$DeleteMe200ResponseSerializer implements PrimitiveSerializer<DeleteMe200Response> {
  @override
  final Iterable<Type> types = const [DeleteMe200Response, _$DeleteMe200Response];

  @override
  final String wireName = r'DeleteMe200Response';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    DeleteMe200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.data != null) {
      yield r'data';
      yield serializers.serialize(
        object.data,
        specifiedType: const FullType(DeleteMe200ResponseAllOfData),
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
    DeleteMe200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required DeleteMe200ResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DeleteMe200ResponseAllOfData),
          ) as DeleteMe200ResponseAllOfData;
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
  DeleteMe200Response deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = DeleteMe200ResponseBuilder();
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

