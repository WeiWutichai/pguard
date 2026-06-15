//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_profile_api/src/model/recruit_candidate.dart';
import 'package:built_collection/built_collection.dart';
import 'package:pguard_profile_api/src/model/api_response_envelope.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'admin_list_candidates200_response.g.dart';

/// AdminListCandidates200Response
///
/// Properties:
/// * [success] 
/// * [error] 
/// * [data] 
@BuiltValue()
abstract class AdminListCandidates200Response implements ApiResponseEnvelope, Built<AdminListCandidates200Response, AdminListCandidates200ResponseBuilder> {
  @BuiltValueField(wireName: r'data')
  BuiltList<RecruitCandidate>? get data;

  AdminListCandidates200Response._();

  factory AdminListCandidates200Response([void updates(AdminListCandidates200ResponseBuilder b)]) = _$AdminListCandidates200Response;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(AdminListCandidates200ResponseBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<AdminListCandidates200Response> get serializer => _$AdminListCandidates200ResponseSerializer();
}

class _$AdminListCandidates200ResponseSerializer implements PrimitiveSerializer<AdminListCandidates200Response> {
  @override
  final Iterable<Type> types = const [AdminListCandidates200Response, _$AdminListCandidates200Response];

  @override
  final String wireName = r'AdminListCandidates200Response';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    AdminListCandidates200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.data != null) {
      yield r'data';
      yield serializers.serialize(
        object.data,
        specifiedType: const FullType(BuiltList, [FullType(RecruitCandidate)]),
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
    AdminListCandidates200Response object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required AdminListCandidates200ResponseBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'data':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(RecruitCandidate)]),
          ) as BuiltList<RecruitCandidate>;
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
  AdminListCandidates200Response deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = AdminListCandidates200ResponseBuilder();
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

