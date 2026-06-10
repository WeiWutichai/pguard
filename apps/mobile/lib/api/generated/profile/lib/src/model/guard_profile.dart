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
/// * [gender] 
/// * [dateOfBirth] 
/// * [yearsOfExperience] 
/// * [previousWorkplace] 
/// * [bankName] 
/// * [accountNumber] - MASKED to its last 4 characters on the owner read (`GET /profile/me`, `POST/PUT /profile/guard`); FULL on the admin endpoints. 
/// * [accountName] 
/// * [approvalStatus] 
@BuiltValue(instantiable: false)
abstract class GuardProfile  {
  @BuiltValueField(wireName: r'user_id')
  String get userId;

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

