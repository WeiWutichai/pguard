//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_profile_api/src/model/approval_status.dart';
import 'package:pguard_profile_api/src/model/date.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'guard_profile.g.dart';

/// GuardProfile
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
/// * [taxId] - Thai national/tax id — the ภ.ง.ด.53 recipient TIN + PromptPay NAT proxy for guard payouts. MASKED to its last 4 characters on the owner read like `account_number`; the FULL value is exposed only over the service-JWT internal payout-profile endpoint. 
/// * [address] 
/// * [emergencyContactName] 
/// * [emergencyContactPhone] 
/// * [emergencyContactRelationship] 
/// * [approvalStatus] 
@BuiltValue(instantiable: false)
abstract class GuardProfile  {
  @BuiltValueField(wireName: r'user_id')
  String get userId;

  /// Guard full name (v1 parity).
  @BuiltValueField(wireName: r'full_name')
  String? get fullName;

  @BuiltValueField(wireName: r'gender')
  String? get gender;

  @BuiltValueField(wireName: r'date_of_birth')
  Date? get dateOfBirth;

  @BuiltValueField(wireName: r'years_of_experience')
  int? get yearsOfExperience;

  @BuiltValueField(wireName: r'previous_workplace')
  String? get previousWorkplace;

  @BuiltValueField(wireName: r'bank_name')
  String? get bankName;

  /// MASKED to its last 4 characters on the owner read (`GET /profile/me`, `POST/PUT /profile/guard`); FULL on the admin endpoints. 
  @BuiltValueField(wireName: r'account_number')
  String? get accountNumber;

  @BuiltValueField(wireName: r'account_name')
  String? get accountName;

  /// Thai national/tax id — the ภ.ง.ด.53 recipient TIN + PromptPay NAT proxy for guard payouts. MASKED to its last 4 characters on the owner read like `account_number`; the FULL value is exposed only over the service-JWT internal payout-profile endpoint. 
  @BuiltValueField(wireName: r'tax_id')
  String? get taxId;

  @BuiltValueField(wireName: r'address')
  String? get address;

  @BuiltValueField(wireName: r'emergency_contact_name')
  String? get emergencyContactName;

  @BuiltValueField(wireName: r'emergency_contact_phone')
  String? get emergencyContactPhone;

  @BuiltValueField(wireName: r'emergency_contact_relationship')
  String? get emergencyContactRelationship;

  @BuiltValueField(wireName: r'approval_status')
  ApprovalStatus get approvalStatus;
  // enum approvalStatusEnum {  pending,  approved,  rejected,  };

  @BuiltValueSerializer(custom: true)
  static Serializer<GuardProfile> get serializer => _$GuardProfileSerializer();
}

class _$GuardProfileSerializer implements PrimitiveSerializer<GuardProfile> {
  @override
  final Iterable<Type> types = const [GuardProfile];

  @override
  final String wireName = r'GuardProfile';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    GuardProfile object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'user_id';
    yield serializers.serialize(
      object.userId,
      specifiedType: const FullType(String),
    );
    if (object.fullName != null) {
      yield r'full_name';
      yield serializers.serialize(
        object.fullName,
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
    if (object.dateOfBirth != null) {
      yield r'date_of_birth';
      yield serializers.serialize(
        object.dateOfBirth,
        specifiedType: const FullType(Date),
      );
    }
    if (object.yearsOfExperience != null) {
      yield r'years_of_experience';
      yield serializers.serialize(
        object.yearsOfExperience,
        specifiedType: const FullType(int),
      );
    }
    if (object.previousWorkplace != null) {
      yield r'previous_workplace';
      yield serializers.serialize(
        object.previousWorkplace,
        specifiedType: const FullType(String),
      );
    }
    if (object.bankName != null) {
      yield r'bank_name';
      yield serializers.serialize(
        object.bankName,
        specifiedType: const FullType(String),
      );
    }
    if (object.accountNumber != null) {
      yield r'account_number';
      yield serializers.serialize(
        object.accountNumber,
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
    if (object.taxId != null) {
      yield r'tax_id';
      yield serializers.serialize(
        object.taxId,
        specifiedType: const FullType(String),
      );
    }
    if (object.address != null) {
      yield r'address';
      yield serializers.serialize(
        object.address,
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
    if (object.emergencyContactPhone != null) {
      yield r'emergency_contact_phone';
      yield serializers.serialize(
        object.emergencyContactPhone,
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
    yield r'approval_status';
    yield serializers.serialize(
      object.approvalStatus,
      specifiedType: const FullType(ApprovalStatus),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    GuardProfile object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  @override
  GuardProfile deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return serializers.deserialize(serialized, specifiedType: FullType($GuardProfile)) as $GuardProfile;
  }
}

/// a concrete implementation of [GuardProfile], since [GuardProfile] is not instantiable
@BuiltValue(instantiable: true)
abstract class $GuardProfile implements GuardProfile, Built<$GuardProfile, $GuardProfileBuilder> {
  $GuardProfile._();

  factory $GuardProfile([void Function($GuardProfileBuilder)? updates]) = _$$GuardProfile;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults($GuardProfileBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<$GuardProfile> get serializer => _$$GuardProfileSerializer();
}

class _$$GuardProfileSerializer implements PrimitiveSerializer<$GuardProfile> {
  @override
  final Iterable<Type> types = const [$GuardProfile, _$$GuardProfile];

  @override
  final String wireName = r'$GuardProfile';

  @override
  Object serialize(
    Serializers serializers,
    $GuardProfile object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return serializers.serialize(object, specifiedType: FullType(GuardProfile))!;
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required GuardProfileBuilder result,
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
        case r'full_name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.fullName = valueDes;
          break;
        case r'gender':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.gender = valueDes;
          break;
        case r'date_of_birth':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(Date),
          ) as Date;
          result.dateOfBirth = valueDes;
          break;
        case r'years_of_experience':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.yearsOfExperience = valueDes;
          break;
        case r'previous_workplace':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.previousWorkplace = valueDes;
          break;
        case r'bank_name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.bankName = valueDes;
          break;
        case r'account_number':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.accountNumber = valueDes;
          break;
        case r'account_name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.accountName = valueDes;
          break;
        case r'tax_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.taxId = valueDes;
          break;
        case r'address':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.address = valueDes;
          break;
        case r'emergency_contact_name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.emergencyContactName = valueDes;
          break;
        case r'emergency_contact_phone':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.emergencyContactPhone = valueDes;
          break;
        case r'emergency_contact_relationship':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.emergencyContactRelationship = valueDes;
          break;
        case r'approval_status':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(ApprovalStatus),
          ) as ApprovalStatus;
          result.approvalStatus = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  $GuardProfile deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = $GuardProfileBuilder();
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

