//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_profile_api/src/model/approval_status.dart';
import 'package:pguard_profile_api/src/model/date.dart';
import 'package:built_collection/built_collection.dart';
import 'package:pguard_profile_api/src/model/my_customer_profile.dart';
import 'package:pguard_profile_api/src/model/my_guard_profile.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';
import 'package:one_of/one_of.dart';

part 'my_profile.g.dart';

/// The caller's own profile, tagged by `kind`. A guard sees `MyGuardProfile` (masked account number); a customer sees `MyCustomerProfile`. 
///
/// Properties:
/// * [kind] 
/// * [userId] 
/// * [fullName] 
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
/// * [companyName] 
/// * [email] 
/// * [contactPhone] - OPTIONAL extra number the customer typed into their own profile (an office line, a site contact, a relative). Frequently blank, and not necessarily this person's own number — it is NOT the account's login phone. See `LoginPhone`. 
@BuiltValue()
abstract class MyProfile implements Built<MyProfile, MyProfileBuilder> {
  /// One Of [MyCustomerProfile], [MyGuardProfile]
  OneOf get oneOf;

  static const String discriminatorFieldName = r'kind';

  static const Map<String, Type> discriminatorMapping = {
    r'MyCustomerProfile': MyCustomerProfile,
    r'MyGuardProfile': MyGuardProfile,
  };

  MyProfile._();

  factory MyProfile([void updates(MyProfileBuilder b)]) = _$MyProfile;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(MyProfileBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<MyProfile> get serializer => _$MyProfileSerializer();
}

extension MyProfileDiscriminatorExt on MyProfile {
    String? get discriminatorValue {
        if (this is MyCustomerProfile) {
            return r'MyCustomerProfile';
        }
        if (this is MyGuardProfile) {
            return r'MyGuardProfile';
        }
        return null;
    }
}
extension MyProfileBuilderDiscriminatorExt on MyProfileBuilder {
    String? get discriminatorValue {
        if (this is MyCustomerProfileBuilder) {
            return r'MyCustomerProfile';
        }
        if (this is MyGuardProfileBuilder) {
            return r'MyGuardProfile';
        }
        return null;
    }
}

class _$MyProfileSerializer implements PrimitiveSerializer<MyProfile> {
  @override
  final Iterable<Type> types = const [MyProfile, _$MyProfile];

  @override
  final String wireName = r'MyProfile';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    MyProfile object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
  }

  @override
  Object serialize(
    Serializers serializers,
    MyProfile object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final oneOf = object.oneOf;
    return serializers.serialize(oneOf.value, specifiedType: FullType(oneOf.valueType))!;
  }

  @override
  MyProfile deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = MyProfileBuilder();
    Object? oneOfDataSrc;
    final serializedList = (serialized as Iterable<Object?>).toList();
    final discIndex = serializedList.indexOf(MyProfile.discriminatorFieldName) + 1;
    final discValue = serializers.deserialize(serializedList[discIndex], specifiedType: FullType(String)) as String;
    oneOfDataSrc = serialized;
    final oneOfTypes = [MyCustomerProfile, MyGuardProfile, ];
    Object oneOfResult;
    Type oneOfType;
    switch (discValue) {
      case r'MyCustomerProfile':
        oneOfResult = serializers.deserialize(
          oneOfDataSrc,
          specifiedType: FullType(MyCustomerProfile),
        ) as MyCustomerProfile;
        oneOfType = MyCustomerProfile;
        break;
      case r'MyGuardProfile':
        oneOfResult = serializers.deserialize(
          oneOfDataSrc,
          specifiedType: FullType(MyGuardProfile),
        ) as MyGuardProfile;
        oneOfType = MyGuardProfile;
        break;
      default:
        throw UnsupportedError("Couldn't deserialize oneOf for the discriminator value: ${discValue}");
    }
    result.oneOf = OneOfDynamic(typeIndex: oneOfTypes.indexOf(oneOfType), types: oneOfTypes, value: oneOfResult);
    return result.build();
  }
}

class MyProfileKindEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'customer')
  static const MyProfileKindEnum customer = _$myProfileKindEnum_customer;

  static Serializer<MyProfileKindEnum> get serializer => _$myProfileKindEnumSerializer;

  const MyProfileKindEnum._(String name): super(name);

  static BuiltSet<MyProfileKindEnum> get values => _$myProfileKindEnumValues;
  static MyProfileKindEnum valueOf(String name) => _$myProfileKindEnumValueOf(name);
}

