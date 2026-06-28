//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_profile_api/src/model/api_response_envelope.dart';
import 'package:pguard_profile_api/src/model/pending_applicants_count.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'admin_pending_applicants_count200_response.g.dart';

/// AdminPendingApplicantsCount200Response
///
/// Properties:
/// * [success] 
/// * [error] 
/// * [data] 
@BuiltValue()
abstract class AdminPendingApplicantsCount200Response implements ApiResponseEnvelope, Built<AdminPendingApplicantsCount200Response, AdminPendingApplicantsCount200ResponseBuilder> {
  @BuiltValueField(wireName: r'data')
  PendingApplicantsCount? get data;

  AdminPendingApplicantsCount200Response._();

  factory AdminPendingApplicantsCount200Response([void updates(AdminPendingApplicantsCount200ResponseBuilder b)]) = _$AdminPendingApplicantsCount200Response;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AdminPendingApplicantsCount200ResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AdminPendingApplicantsCount200Response> get serializer => _$AdminPendingApplicantsCount200ResponseSerializer();
}

class _$AdminPendingApplicantsCount200ResponseSerializer implements PrimitiveSerializer<AdminPendingApplicantsCount200Response> {
  @override
  final Iterable<Type> types = const [AdminPendingApplicantsCount200Response, _$AdminPendingApplicantsCount200Response];

  @override
  final String wireName = r'AdminPendingApplicantsCount200Response';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AdminPendingApplicantsCount200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.data != null) {
      yield r'data';
      yield serializers.serialize(
        object.data,
        specifiedType: const FullType(PendingApplicantsCount),
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
    AdminPendingApplicantsCount200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required AdminPendingApplicantsCount200ResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(PendingApplicantsCount),
          ) as PendingApplicantsCount;
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
  AdminPendingApplicantsCount200Response deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AdminPendingApplicantsCount200ResponseBuilder();
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

