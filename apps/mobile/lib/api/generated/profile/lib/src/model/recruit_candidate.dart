//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_profile_api/src/model/approval_status.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'recruit_candidate.g.dart';

/// A guard in the recruitment pipeline (lean projection — no PII).
///
/// Properties:
/// * [userId] 
/// * [yearsOfExperience] 
/// * [approvalStatus] 
/// * [recruitmentStage] 
@BuiltValue()
abstract class RecruitCandidate implements Built<RecruitCandidate, RecruitCandidateBuilder> {
  @BuiltValueField(wireName: r'user_id')
  String get userId;

  @BuiltValueField(wireName: r'years_of_experience')
  int? get yearsOfExperience;

  @BuiltValueField(wireName: r'approval_status')
  ApprovalStatus get approvalStatus;
  // enum approvalStatusEnum {  pending,  approved,  rejected,  };

  @BuiltValueField(wireName: r'recruitment_stage')
  RecruitCandidateRecruitmentStageEnum get recruitmentStage;
  // enum recruitmentStageEnum {  sourcing,  screened,  docs_verified,  };

  RecruitCandidate._();

  factory RecruitCandidate([void updates(RecruitCandidateBuilder b)]) = _$RecruitCandidate;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(RecruitCandidateBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<RecruitCandidate> get serializer => _$RecruitCandidateSerializer();
}

class _$RecruitCandidateSerializer implements PrimitiveSerializer<RecruitCandidate> {
  @override
  final Iterable<Type> types = const [RecruitCandidate, _$RecruitCandidate];

  @override
  final String wireName = r'RecruitCandidate';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    RecruitCandidate object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'user_id';
    yield serializers.serialize(
      object.userId,
      specifiedType: const FullType(String),
    );
    if (object.yearsOfExperience != null) {
      yield r'years_of_experience';
      yield serializers.serialize(
        object.yearsOfExperience,
        specifiedType: const FullType(int),
      );
    }
    yield r'approval_status';
    yield serializers.serialize(
      object.approvalStatus,
      specifiedType: const FullType(ApprovalStatus),
    );
    yield r'recruitment_stage';
    yield serializers.serialize(
      object.recruitmentStage,
      specifiedType: const FullType(RecruitCandidateRecruitmentStageEnum),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    RecruitCandidate object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required RecruitCandidateBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'user_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.userId = valueDes;
          break;
        case r'years_of_experience':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.yearsOfExperience = valueDes;
          break;
        case r'approval_status':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ApprovalStatus),
          ) as ApprovalStatus;
          result.approvalStatus = valueDes;
          break;
        case r'recruitment_stage':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(RecruitCandidateRecruitmentStageEnum),
          ) as RecruitCandidateRecruitmentStageEnum;
          result.recruitmentStage = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  RecruitCandidate deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = RecruitCandidateBuilder();
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

class RecruitCandidateRecruitmentStageEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'sourcing')
  static const RecruitCandidateRecruitmentStageEnum sourcing = _$recruitCandidateRecruitmentStageEnum_sourcing;
  @BuiltValueEnumConst(wireName: r'screened')
  static const RecruitCandidateRecruitmentStageEnum screened = _$recruitCandidateRecruitmentStageEnum_screened;
  @BuiltValueEnumConst(wireName: r'docs_verified')
  static const RecruitCandidateRecruitmentStageEnum docsVerified = _$recruitCandidateRecruitmentStageEnum_docsVerified;

  static Serializer<RecruitCandidateRecruitmentStageEnum> get serializer => _$recruitCandidateRecruitmentStageEnumSerializer;

  const RecruitCandidateRecruitmentStageEnum._(String name): super(name);

  static BuiltSet<RecruitCandidateRecruitmentStageEnum> get values => _$recruitCandidateRecruitmentStageEnumValues;
  static RecruitCandidateRecruitmentStageEnum valueOf(String name) => _$recruitCandidateRecruitmentStageEnumValueOf(name);
}

