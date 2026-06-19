//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_profile_api/src/model/approval_status.dart';
import 'package:pguard_profile_api/src/model/date.dart';
import 'package:pguard_profile_api/src/model/guard_profile.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'inline_object1_all_of_data.g.dart';

/// InlineObject1AllOfData
///
/// Properties:
/// * [userId] 
/// * [fullName] - Guard full name (v1 parity).
/// * [gender] 
/// * [dateOfBirth] 
/// * [yearsOfExperience] 
/// * [previousWorkplace] 
/// * [bankName] 
/// * [accountNumber] - MASKED to its last 4 characters on the owner read (`GET /profile/me`, `POST/PUT /profile/guard`); FULL on the admin endpoints. 
/// * [accountName] 
/// * [address] 
/// * [emergencyContactName] 
/// * [emergencyContactPhone] 
/// * [emergencyContactRelationship] 
/// * [approvalStatus] 
/// * [docUploadToken] - Short-lived (~30 min) Bearer token for credential-image uploads.
@BuiltValue()
abstract class InlineObject1AllOfData implements GuardProfile, Built<InlineObject1AllOfData, InlineObject1AllOfDataBuilder> {
  /// Short-lived (~30 min) Bearer token for credential-image uploads.
  @BuiltValueField(wireName: r'doc_upload_token')
  String get docUploadToken;

  InlineObject1AllOfData._();

  factory InlineObject1AllOfData([void updates(InlineObject1AllOfDataBuilder b)]) = _$InlineObject1AllOfData;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(InlineObject1AllOfDataBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<InlineObject1AllOfData> get serializer => _$InlineObject1AllOfDataSerializer();
}

class _$InlineObject1AllOfDataSerializer implements PrimitiveSerializer<InlineObject1AllOfData> {
  @override
  final Iterable<Type> types = const [InlineObject1AllOfData, _$InlineObject1AllOfData];

  @override
  final String wireName = r'InlineObject1AllOfData';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    InlineObject1AllOfData object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'approval_status';
    yield serializers.serialize(
      object.approvalStatus,
      specifiedType: const FullType(ApprovalStatus),
    );
    if (object.address != null) {
      yield r'address';
      yield serializers.serialize(
        object.address,
        specifiedType: const FullType(String),
      );
    }
    if (object.gender != null) {
      yield r'gender';
      yield serializers.serialize(
        object.gender,
        specifiedType: const FullType(String),
      );
    }
    if (object.accountName != null) {
      yield r'account_name';
      yield serializers.serialize(
        object.accountName,
        specifiedType: const FullType(String),
      );
    }
    if (object.emergencyContactName != null) {
      yield r'emergency_contact_name';
      yield serializers.serialize(
        object.emergencyContactName,
        specifiedType: const FullType(String),
      );
    }
    if (object.previousWorkplace != null) {
      yield r'previous_workplace';
      yield serializers.serialize(
        object.previousWorkplace,
        specifiedType: const FullType(String),
      );
    }
    if (object.emergencyContactRelationship != null) {
      yield r'emergency_contact_relationship';
      yield serializers.serialize(
        object.emergencyContactRelationship,
        specifiedType: const FullType(String),
      );
    }
    if (object.fullName != null) {
      yield r'full_name';
      yield serializers.serialize(
        object.fullName,
        specifiedType: const FullType(String),
      );
    }
    if (object.dateOfBirth != null) {
      yield r'date_of_birth';
      yield serializers.serialize(
        object.dateOfBirth,
        specifiedType: const FullType(Date),
      );
    }
    if (object.bankName != null) {
      yield r'bank_name';
      yield serializers.serialize(
        object.bankName,
        specifiedType: const FullType(String),
      );
    }
    yield r'doc_upload_token';
    yield serializers.serialize(
      object.docUploadToken,
      specifiedType: const FullType(String),
    );
    if (object.accountNumber != null) {
      yield r'account_number';
      yield serializers.serialize(
        object.accountNumber,
        specifiedType: const FullType(String),
      );
    }
    yield r'user_id';
    yield serializers.serialize(
      object.userId,
      specifiedType: const FullType(String),
    );
    if (object.emergencyContactPhone != null) {
      yield r'emergency_contact_phone';
      yield serializers.serialize(
        object.emergencyContactPhone,
        specifiedType: const FullType(String),
      );
    }
    if (object.yearsOfExperience != null) {
      yield r'years_of_experience';
      yield serializers.serialize(
        object.yearsOfExperience,
        specifiedType: const FullType(int),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    InlineObject1AllOfData object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required InlineObject1AllOfDataBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'approval_status':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ApprovalStatus),
          ) as ApprovalStatus;
          result.approvalStatus = valueDes;
          break;
        case r'address':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.address = valueDes;
          break;
        case r'gender':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.gender = valueDes;
          break;
        case r'account_name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.accountName = valueDes;
          break;
        case r'emergency_contact_name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.emergencyContactName = valueDes;
          break;
        case r'previous_workplace':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.previousWorkplace = valueDes;
          break;
        case r'emergency_contact_relationship':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.emergencyContactRelationship = valueDes;
          break;
        case r'full_name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.fullName = valueDes;
          break;
        case r'date_of_birth':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(Date),
          ) as Date;
          result.dateOfBirth = valueDes;
          break;
        case r'bank_name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.bankName = valueDes;
          break;
        case r'doc_upload_token':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.docUploadToken = valueDes;
          break;
        case r'account_number':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.accountNumber = valueDes;
          break;
        case r'user_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.userId = valueDes;
          break;
        case r'emergency_contact_phone':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.emergencyContactPhone = valueDes;
          break;
        case r'years_of_experience':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.yearsOfExperience = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  InlineObject1AllOfData deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = InlineObject1AllOfDataBuilder();
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

