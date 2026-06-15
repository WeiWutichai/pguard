//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:pguard_calling_api/src/model/api_response_envelope.dart';
import 'package:pguard_calling_api/src/model/call.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'admin_list_calls200_response.g.dart';

/// AdminListCalls200Response
///
/// Properties:
/// * [success] 
/// * [error] 
/// * [data] 
@BuiltValue()
abstract class AdminListCalls200Response implements ApiResponseEnvelope, Built<AdminListCalls200Response, AdminListCalls200ResponseBuilder> {
  @BuiltValueField(wireName: r'data')
  BuiltList<Call>? get data;

  AdminListCalls200Response._();

  factory AdminListCalls200Response([void updates(AdminListCalls200ResponseBuilder b)]) = _$AdminListCalls200Response;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AdminListCalls200ResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AdminListCalls200Response> get serializer => _$AdminListCalls200ResponseSerializer();
}

class _$AdminListCalls200ResponseSerializer implements PrimitiveSerializer<AdminListCalls200Response> {
  @override
  final Iterable<Type> types = const [AdminListCalls200Response, _$AdminListCalls200Response];

  @override
  final String wireName = r'AdminListCalls200Response';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AdminListCalls200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.data != null) {
      yield r'data';
      yield serializers.serialize(
        object.data,
        specifiedType: const FullType(BuiltList, [FullType(Call)]),
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
    AdminListCalls200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required AdminListCalls200ResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(Call)]),
          ) as BuiltList<Call>;
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
  AdminListCalls200Response deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AdminListCalls200ResponseBuilder();
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

