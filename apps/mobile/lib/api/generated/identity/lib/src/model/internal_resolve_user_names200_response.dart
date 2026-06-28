//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:pguard_identity_api/src/model/api_response_envelope.dart';
import 'package:pguard_identity_api/src/model/resolved_user.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'internal_resolve_user_names200_response.g.dart';

/// InternalResolveUserNames200Response
///
/// Properties:
/// * [success] 
/// * [error] 
/// * [data] 
@BuiltValue()
abstract class InternalResolveUserNames200Response implements ApiResponseEnvelope, Built<InternalResolveUserNames200Response, InternalResolveUserNames200ResponseBuilder> {
  @BuiltValueField(wireName: r'data')
  BuiltMap<String, ResolvedUser>? get data;

  InternalResolveUserNames200Response._();

  factory InternalResolveUserNames200Response([void updates(InternalResolveUserNames200ResponseBuilder b)]) = _$InternalResolveUserNames200Response;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(InternalResolveUserNames200ResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<InternalResolveUserNames200Response> get serializer => _$InternalResolveUserNames200ResponseSerializer();
}

class _$InternalResolveUserNames200ResponseSerializer implements PrimitiveSerializer<InternalResolveUserNames200Response> {
  @override
  final Iterable<Type> types = const [InternalResolveUserNames200Response, _$InternalResolveUserNames200Response];

  @override
  final String wireName = r'InternalResolveUserNames200Response';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    InternalResolveUserNames200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.data != null) {
      yield r'data';
      yield serializers.serialize(
        object.data,
        specifiedType: const FullType(BuiltMap, [FullType(String), FullType(ResolvedUser)]),
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
    InternalResolveUserNames200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required InternalResolveUserNames200ResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltMap, [FullType(String), FullType(ResolvedUser)]),
          ) as BuiltMap<String, ResolvedUser>;
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
  InternalResolveUserNames200Response deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = InternalResolveUserNames200ResponseBuilder();
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

