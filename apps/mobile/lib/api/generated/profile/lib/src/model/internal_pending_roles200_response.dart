//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:pguard_profile_api/src/model/api_response_envelope.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'internal_pending_roles200_response.g.dart';

/// InternalPendingRoles200Response
///
/// Properties:
/// * [success] 
/// * [error] 
/// * [data] 
@BuiltValue()
abstract class InternalPendingRoles200Response implements ApiResponseEnvelope, Built<InternalPendingRoles200Response, InternalPendingRoles200ResponseBuilder> {
  @BuiltValueField(wireName: r'data')
  BuiltList<String>? get data;

  InternalPendingRoles200Response._();

  factory InternalPendingRoles200Response([void updates(InternalPendingRoles200ResponseBuilder b)]) = _$InternalPendingRoles200Response;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(InternalPendingRoles200ResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<InternalPendingRoles200Response> get serializer => _$InternalPendingRoles200ResponseSerializer();
}

class _$InternalPendingRoles200ResponseSerializer implements PrimitiveSerializer<InternalPendingRoles200Response> {
  @override
  final Iterable<Type> types = const [InternalPendingRoles200Response, _$InternalPendingRoles200Response];

  @override
  final String wireName = r'InternalPendingRoles200Response';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    InternalPendingRoles200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.data != null) {
      yield r'data';
      yield serializers.serialize(
        object.data,
        specifiedType: const FullType(BuiltList, [FullType(String)]),
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
    InternalPendingRoles200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required InternalPendingRoles200ResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
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
  InternalPendingRoles200Response deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = InternalPendingRoles200ResponseBuilder();
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

