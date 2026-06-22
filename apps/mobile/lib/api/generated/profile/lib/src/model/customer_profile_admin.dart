//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_profile_api/src/model/approval_status.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'customer_profile_admin.g.dart';

/// A customer profile row in the admin directory. Adds `created_at` (signup time / the list's order key) and `approval_status` (the customer review queue's pending/approved filter) to the owner-facing shape. Customers are now admin-approved exactly like guards (no longer auto-approved on first profile insert); `approval_status` is owned on `profile.customer_profiles`. 
///
/// Properties:
/// * [userId] 
/// * [fullName] 
/// * [address] 
/// * [companyName] 
/// * [email] 
/// * [contactPhone] 
/// * [createdAt] 
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

  @BuiltValueField(wireName: r'contact_phone')
  String? get contactPhone;

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

