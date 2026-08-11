//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:pguard_profile_api/src/model/api_response_envelope.dart';
import 'package:pguard_profile_api/src/model/guard_profile_admin.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'admin_list_guard_profiles200_response.g.dart';

/// AdminListGuardProfiles200Response
///
/// Properties:
/// * [success] 
/// * [error] 
/// * [data] 
@BuiltValue()
abstract class AdminListGuardProfiles200Response implements ApiResponseEnvelope, Built<AdminListGuardProfiles200Response, AdminListGuardProfiles200ResponseBuilder> {
  @BuiltValueField(wireName: r'data')
  BuiltList<GuardProfileAdmin>? get data;

  AdminListGuardProfiles200Response._();

  factory AdminListGuardProfiles200Response([void updates(AdminListGuardProfiles200ResponseBuilder b)]) = _$AdminListGuardProfiles200Response;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AdminListGuardProfiles200ResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AdminListGuardProfiles200Response> get serializer => _$AdminListGuardProfiles200ResponseSerializer();
}

class _$AdminListGuardProfiles200ResponseSerializer implements PrimitiveSerializer<AdminListGuardProfiles200Response> {
  @override
  final Iterable<Type> types = const [AdminListGuardProfiles200Response, _$AdminListGuardProfiles200Response];

  @override
  final String wireName = r'AdminListGuardProfiles200Response';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AdminListGuardProfiles200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.data != null) {
      yield r'data';
      yield serializers.serialize(
        object.data,
        specifiedType: const FullType(BuiltList, [FullType(GuardProfileAdmin)]),
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
    AdminListGuardProfiles200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required AdminListGuardProfiles200ResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(GuardProfileAdmin)]),
          ) as BuiltList<GuardProfileAdmin>;
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
  AdminListGuardProfiles200Response deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AdminListGuardProfiles200ResponseBuilder();
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

