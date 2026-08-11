//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_profile_api/src/model/approval_status.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'customer_profile_admin.g.dart';

/// A customer profile row in the admin directory. Adds `created_at` (signup time / the list's order key), `approval_status` (the customer review queue's pending/approved filter) and `login_phone` (the account's own number, from identity) to the owner-facing shape. Customers are now admin-approved exactly like guards (no longer auto-approved on first profile insert); `approval_status` is owned on `profile.customer_profiles`.  NOTE for consumers: `login_phone` and `contact_phone` are DIFFERENT numbers. Reading `contact_phone` as \"the applicant's phone\" is what left the approval queue showing a bare short id and a \"—\" contact for a real, reachable person. 
///
/// Properties:
/// * [userId] 
/// * [fullName] 
/// * [address] 
/// * [companyName] 
/// * [email] 
/// * [contactPhone] - OPTIONAL extra number the customer typed into their own profile (an office line, a site contact, a relative). Frequently blank, and not necessarily this person's own number — it is NOT the account's login phone. Use `login_phone` to reach the applicant; show `contact_phone` only as an additional detail. 
/// * [loginPhone] - The ACCOUNT'S OWN phone number — `identity.users.phone`, the number this person registered with and signs in with (it is the OTP login key, so every live account has exactly one and it is always present). Resolved per request from identity's service-JWT'd `POST /internal/users/names`; `null` ONLY when identity is unreachable or the account no longer exists — never for a healthy row.  NOT to be confused with `contact_phone` on a customer profile, which is an OPTIONAL extra the customer may type in (often blank, and may be a third party's number), nor with a guard's `emergency_contact_phone`. When an admin needs to CALL an applicant, this is the number. Admin-surface PII: never log it or expose it outside the admin SPA. 
/// * [createdAt] - Signup time — also the list's order-by key.
/// * [approvalStatus] 
@BuiltValue()
abstract class CustomerProfileAdmin implements Built<CustomerProfileAdmin, CustomerProfileAdminBuilder> {
  @BuiltValueField(wireName: r'user_id')
  String get userId;

  @BuiltValueField(wireName: r'full_name')
  String? get fullName;

  @BuiltValueField(wireName: r'address')
  String? get address;

  @BuiltValueField(wireName: r'company_name')
  String? get companyName;

  @BuiltValueField(wireName: r'email')
  String? get email;

  /// OPTIONAL extra number the customer typed into their own profile (an office line, a site contact, a relative). Frequently blank, and not necessarily this person's own number — it is NOT the account's login phone. Use `login_phone` to reach the applicant; show `contact_phone` only as an additional detail. 
  @BuiltValueField(wireName: r'contact_phone')
  String? get contactPhone;

  /// The ACCOUNT'S OWN phone number — `identity.users.phone`, the number this person registered with and signs in with (it is the OTP login key, so every live account has exactly one and it is always present). Resolved per request from identity's service-JWT'd `POST /internal/users/names`; `null` ONLY when identity is unreachable or the account no longer exists — never for a healthy row.  NOT to be confused with `contact_phone` on a customer profile, which is an OPTIONAL extra the customer may type in (often blank, and may be a third party's number), nor with a guard's `emergency_contact_phone`. When an admin needs to CALL an applicant, this is the number. Admin-surface PII: never log it or expose it outside the admin SPA. 
  @BuiltValueField(wireName: r'login_phone')
  String? get loginPhone;

  /// Signup time — also the list's order-by key.
  @BuiltValueField(wireName: r'created_at')
  DateTime get createdAt;

  @BuiltValueField(wireName: r'approval_status')
  ApprovalStatus get approvalStatus;
  // enum approvalStatusEnum {  pending,  approved,  rejected,  };

  CustomerProfileAdmin._();

  factory CustomerProfileAdmin([void updates(CustomerProfileAdminBuilder b)]) = _$CustomerProfileAdmin;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CustomerProfileAdminBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<CustomerProfileAdmin> get serializer => _$CustomerProfileAdminSerializer();
}

class _$CustomerProfileAdminSerializer implements PrimitiveSerializer<CustomerProfileAdmin> {
  @override
  final Iterable<Type> types = const [CustomerProfileAdmin, _$CustomerProfileAdmin];

  @override
  final String wireName = r'CustomerProfileAdmin';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CustomerProfileAdmin object, {
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
    if (object.address != null) {
      yield r'address';
      yield serializers.serialize(
        object.address,
        specifiedType: const FullType(String),
      );
    }
    if (object.companyName != null) {
      yield r'company_name';
      yield serializers.serialize(
        object.companyName,
        specifiedType: const FullType(String),
      );
    }
    if (object.email != null) {
      yield r'email';
      yield serializers.serialize(
        object.email,
        specifiedType: const FullType(String),
      );
    }
    if (object.contactPhone != null) {
      yield r'contact_phone';
      yield serializers.serialize(
        object.contactPhone,
        specifiedType: const FullType(String),
      );
    }
    if (object.loginPhone != null) {
      yield r'login_phone';
      yield serializers.serialize(
        object.loginPhone,
        specifiedType: const FullType(String),
      );
    }
    yield r'created_at';
    yield serializers.serialize(
      object.createdAt,
      specifiedType: const FullType(DateTime),
    );
    yield r'approval_status';
    yield serializers.serialize(
      object.approvalStatus,
      specifiedType: const FullType(ApprovalStatus),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    CustomerProfileAdmin object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required CustomerProfileAdminBuilder result,
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
        case r'address':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.address = valueDes;
          break;
        case r'company_name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.companyName = valueDes;
          break;
        case r'email':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.email = valueDes;
          break;
        case r'contact_phone':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.contactPhone = valueDes;
          break;
        case r'login_phone':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.loginPhone = valueDes;
          break;
        case r'created_at':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.createdAt = valueDes;
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
  CustomerProfileAdmin deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CustomerProfileAdminBuilder();
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

