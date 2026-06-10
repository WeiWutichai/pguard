//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_profile_api/src/model/approval_status.dart';
import 'package:pguard_profile_api/src/model/date.dart';
import 'package:built_collection/built_collection.dart';
import 'package:pguard_profile_api/src/model/guard_profile.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'my_guard_profile.g.dart';

/// MyGuardProfile
///
/// Properties:
/// * [userId] 
/// * [gender] 
/// * [dateOfBirth] 
/// * [yearsOfExperience] 
/// * [previousWorkplace] 
/// * [bankName] 
/// * [accountNumber] - MASKED to its last 4 characters on the owner read (`GET /profile/me`, `POST/PUT /profile/guard`); FULL on the admin endpoints. 
/// * [accountName] 
/// * [approvalStatus] 
/// * [kind] 
@BuiltValue()
abstract class MyGuardProfile implements GuardProfile, Built<MyGuardProfile, MyGuardProfileBuilder> {
  @BuiltValueField(wireName: r'kind')
  MyGuardProfileKindEnum get kind;
  // enum kindEnum {  guard,  };

  MyGuardProfile._();

  factory MyGuardProfile([void updates(MyGuardProfileBuilder b)]) = _$MyGuardProfile;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(MyGuardProfileBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<MyGuardProfile> get serializer => _$MyGuardProfileSerializer();
}

class _$MyGuardProfileSerializer implements PrimitiveSerializer<MyGuardProfile> {
  @override
  final Iterable<Type> types = const [MyGuardProfile, _$MyGuardProfile];

  @override
  final String wireName = r'MyGuardProfile';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    MyGuardProfile object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'approval_status';
    yield serializers.serialize(
      object.approvalStatus,
      specifiedType: const FullType(ApprovalStatus),
    );
    if (object.gender != null) {
      yield r'gender';
      yield serializers.serialize(
        object.gender,
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
    if (object.accountName != null) {
      yield r'account_name';
      yield serializers.serialize(
        object.accountName,
        specifiedType: const FullType(String),
      );
    }
    yield r'kind';
    yield serializers.serialize(
      object.kind,
      specifiedType: const FullType(MyGuardProfileKindEnum),
    );
    if (object.previousWorkplace != null) {
      yield r'previous_workplace';
      yield serializers.serialize(
        object.previousWorkplace,
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
  }

  @override
  Object serialize(
    Serializers serializers,
    MyGuardProfile object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required MyGuardProfileBuilder result,
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
        case r'gender':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.gender = valueDes;
          break;
        case r'years_of_experience':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.yearsOfExperience = valueDes;
          break;
        case r'account_name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.accountName = valueDes;
          break;
        case r'kind':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(MyGuardProfileKindEnum),
          ) as MyGuardProfileKindEnum;
          result.kind = valueDes;
          break;
        case r'previous_workplace':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.previousWorkplace = valueDes;
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
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  MyGuardProfile deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = MyGuardProfileBuilder();
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

class MyGuardProfileKindEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'guard')
  static const MyGuardProfileKindEnum guard = _$myGuardProfileKindEnum_guard;

  static Serializer<MyGuardProfileKindEnum> get serializer => _$myGuardProfileKindEnumSerializer;

  const MyGuardProfileKindEnum._(String name): super(name);

  static BuiltSet<MyGuardProfileKindEnum> get values => _$myGuardProfileKindEnumValues;
  static MyGuardProfileKindEnum valueOf(String name) => _$myGuardProfileKindEnumValueOf(name);
}

