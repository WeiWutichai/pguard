//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:pguard_profile_api/src/model/api_response_envelope.dart';
import 'package:pguard_profile_api/src/model/resolved_name.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'admin_resolve_user_names200_response.g.dart';

/// AdminResolveUserNames200Response
///
/// Properties:
/// * [success] 
/// * [error] 
/// * [data] - id (uuid string) → resolved name. Unknown ids are omitted.
@BuiltValue()
abstract class AdminResolveUserNames200Response implements ApiResponseEnvelope, Built<AdminResolveUserNames200Response, AdminResolveUserNames200ResponseBuilder> {
  /// id (uuid string) → resolved name. Unknown ids are omitted.
  @BuiltValueField(wireName: r'data')
  BuiltMap<String, ResolvedName>? get data;

  AdminResolveUserNames200Response._();

  factory AdminResolveUserNames200Response([void updates(AdminResolveUserNames200ResponseBuilder b)]) = _$AdminResolveUserNames200Response;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AdminResolveUserNames200ResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AdminResolveUserNames200Response> get serializer => _$AdminResolveUserNames200ResponseSerializer();
}

class _$AdminResolveUserNames200ResponseSerializer implements PrimitiveSerializer<AdminResolveUserNames200Response> {
  @override
  final Iterable<Type> types = const [AdminResolveUserNames200Response, _$AdminResolveUserNames200Response];

  @override
  final String wireName = r'AdminResolveUserNames200Response';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AdminResolveUserNames200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.data != null) {
      yield r'data';
      yield serializers.serialize(
        object.data,
        specifiedType: const FullType(BuiltMap, [FullType(String), FullType(ResolvedName)]),
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
    AdminResolveUserNames200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required AdminResolveUserNames200ResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltMap, [FullType(String), FullType(ResolvedName)]),
          ) as BuiltMap<String, ResolvedName>;
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
  AdminResolveUserNames200Response deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AdminResolveUserNames200ResponseBuilder();
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

