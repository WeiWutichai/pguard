//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_profile_api/src/model/recruit_candidate.dart';
import 'package:pguard_profile_api/src/model/api_response_envelope.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'admin_set_candidate_stage200_response.g.dart';

/// AdminSetCandidateStage200Response
///
/// Properties:
/// * [success] 
/// * [error] 
/// * [data] 
@BuiltValue()
abstract class AdminSetCandidateStage200Response implements ApiResponseEnvelope, Built<AdminSetCandidateStage200Response, AdminSetCandidateStage200ResponseBuilder> {
  @BuiltValueField(wireName: r'data')
  RecruitCandidate? get data;

  AdminSetCandidateStage200Response._();

  factory AdminSetCandidateStage200Response([void updates(AdminSetCandidateStage200ResponseBuilder b)]) = _$AdminSetCandidateStage200Response;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AdminSetCandidateStage200ResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AdminSetCandidateStage200Response> get serializer => _$AdminSetCandidateStage200ResponseSerializer();
}

class _$AdminSetCandidateStage200ResponseSerializer implements PrimitiveSerializer<AdminSetCandidateStage200Response> {
  @override
  final Iterable<Type> types = const [AdminSetCandidateStage200Response, _$AdminSetCandidateStage200Response];

  @override
  final String wireName = r'AdminSetCandidateStage200Response';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AdminSetCandidateStage200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.data != null) {
      yield r'data';
      yield serializers.serialize(
        object.data,
        specifiedType: const FullType(RecruitCandidate),
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
    AdminSetCandidateStage200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required AdminSetCandidateStage200ResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(RecruitCandidate),
          ) as RecruitCandidate;
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
  AdminSetCandidateStage200Response deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AdminSetCandidateStage200ResponseBuilder();
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

