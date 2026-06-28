//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:pguard_identity_api/src/model/api_response_envelope.dart';
import 'package:pguard_identity_api/src/model/user_search_result.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'admin_search_users200_response.g.dart';

/// AdminSearchUsers200Response
///
/// Properties:
/// * [success] 
/// * [error] 
/// * [data] 
@BuiltValue()
abstract class AdminSearchUsers200Response implements ApiResponseEnvelope, Built<AdminSearchUsers200Response, AdminSearchUsers200ResponseBuilder> {
  @BuiltValueField(wireName: r'data')
  BuiltList<UserSearchResult>? get data;

  AdminSearchUsers200Response._();

  factory AdminSearchUsers200Response([void updates(AdminSearchUsers200ResponseBuilder b)]) = _$AdminSearchUsers200Response;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AdminSearchUsers200ResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AdminSearchUsers200Response> get serializer => _$AdminSearchUsers200ResponseSerializer();
}

class _$AdminSearchUsers200ResponseSerializer implements PrimitiveSerializer<AdminSearchUsers200Response> {
  @override
  final Iterable<Type> types = const [AdminSearchUsers200Response, _$AdminSearchUsers200Response];

  @override
  final String wireName = r'AdminSearchUsers200Response';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AdminSearchUsers200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.data != null) {
      yield r'data';
      yield serializers.serialize(
        object.data,
        specifiedType: const FullType(BuiltList, [FullType(UserSearchResult)]),
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
    AdminSearchUsers200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required AdminSearchUsers200ResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(UserSearchResult)]),
          ) as BuiltList<UserSearchResult>;
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
  AdminSearchUsers200Response deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AdminSearchUsers200ResponseBuilder();
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

