//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_profile_api/src/model/approval_status.dart';
import 'package:pguard_profile_api/src/model/date.dart';
import 'package:pguard_profile_api/src/model/guard_profile.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'guard_profile_admin.g.dart';

/// A guard profile row as returned to an ADMIN (`GET /admin/guard-profiles` — the approval queue). Everything in the owner-facing `GuardProfile` (with the FULL account number) PLUS the two fields a reviewer needs to know WHO they are approving: `created_at` (when the person signed up) and `login_phone` (the number that person can actually be called on). A SEPARATE shape from `GuardProfile` so the owner-facing read stays additive-only and never carries the identity-owned phone. 
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
/// * [createdAt] - Signup time (`guard_profiles.created_at`) — also the list's order-by key.
/// * [loginPhone] - The ACCOUNT'S OWN phone number — `identity.users.phone`, the number this person registered with and signs in with (it is the OTP login key, so every live account has exactly one and it is always present). Resolved per request from identity's service-JWT'd `POST /internal/users/names`; `null` ONLY when identity is unreachable or the account no longer exists — never for a healthy row.  NOT to be confused with `contact_phone` on a customer profile, which is an OPTIONAL extra the customer may type in (often blank, and may be a third party's number), nor with a guard's `emergency_contact_phone`. When an admin needs to CALL an applicant, this is the number. Admin-surface PII: never log it or expose it outside the admin SPA. 
@BuiltValue()
abstract class GuardProfileAdmin implements GuardProfile, Built<GuardProfileAdmin, GuardProfileAdminBuilder> {
  /// Signup time (`guard_profiles.created_at`) — also the list's order-by key.
  @BuiltValueField(wireName: r'created_at')
  DateTime get createdAt;

  /// The ACCOUNT'S OWN phone number — `identity.users.phone`, the number this person registered with and signs in with (it is the OTP login key, so every live account has exactly one and it is always present). Resolved per request from identity's service-JWT'd `POST /internal/users/names`; `null` ONLY when identity is unreachable or the account no longer exists — never for a healthy row.  NOT to be confused with `contact_phone` on a customer profile, which is an OPTIONAL extra the customer may type in (often blank, and may be a third party's number), nor with a guard's `emergency_contact_phone`. When an admin needs to CALL an applicant, this is the number. Admin-surface PII: never log it or expose it outside the admin SPA. 
  @BuiltValueField(wireName: r'login_phone')
  String? get loginPhone;

  GuardProfileAdmin._();

  factory GuardProfileAdmin([void updates(GuardProfileAdminBuilder b)]) = _$GuardProfileAdmin;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(GuardProfileAdminBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<GuardProfileAdmin> get serializer => _$GuardProfileAdminSerializer();
}

class _$GuardProfileAdminSerializer implements PrimitiveSerializer<GuardProfileAdmin> {
  @override
  final Iterable<Type> types = const [GuardProfileAdmin, _$GuardProfileAdmin];

  @override
  final String wireName = r'GuardProfileAdmin';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    GuardProfileAdmin object, {
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
    yield r'created_at';
    yield serializers.serialize(
      object.createdAt,
      specifiedType: const FullType(DateTime),
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
    if (object.loginPhone != null) {
      yield r'login_phone';
      yield serializers.serialize(
        object.loginPhone,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    GuardProfileAdmin object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required GuardProfileAdminBuilder result,
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
        case r'created_at':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.createdAt = valueDes;
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
        case r'login_phone':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.loginPhone = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  GuardProfileAdmin deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = GuardProfileAdminBuilder();
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

