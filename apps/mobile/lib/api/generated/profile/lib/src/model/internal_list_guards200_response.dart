//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_profile_api/src/model/internal_guard.dart';
import 'package:built_collection/built_collection.dart';
import 'package:pguard_profile_api/src/model/api_response_envelope.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'internal_list_guards200_response.g.dart';

/// InternalListGuards200Response
///
/// Properties:
/// * [success] 
/// * [error] 
/// * [data] 
@BuiltValue()
abstract class InternalListGuards200Response implements ApiResponseEnvelope, Built<InternalListGuards200Response, InternalListGuards200ResponseBuilder> {
  @BuiltValueField(wireName: r'data')
  BuiltList<InternalGuard>? get data;

  InternalListGuards200Response._();

  factory InternalListGuards200Response([void updates(InternalListGuards200ResponseBuilder b)]) = _$InternalListGuards200Response;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(InternalListGuards200ResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<InternalListGuards200Response> get serializer => _$InternalListGuards200ResponseSerializer();
}

class _$InternalListGuards200ResponseSerializer implements PrimitiveSerializer<InternalListGuards200Response> {
  @override
  final Iterable<Type> types = const [InternalListGuards200Response, _$InternalListGuards200Response];

  @override
  final String wireName = r'InternalListGuards200Response';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    InternalListGuards200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.data != null) {
      yield r'data';
      yield serializers.serialize(
        object.data,
        specifiedType: const FullType(BuiltList, [FullType(InternalGuard)]),
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
    InternalListGuards200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required InternalListGuards200ResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(InternalGuard)]),
          ) as BuiltList<InternalGuard>;
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
  InternalListGuards200Response deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = InternalListGuards200ResponseBuilder();
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

