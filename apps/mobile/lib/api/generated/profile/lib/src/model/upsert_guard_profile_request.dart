//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_profile_api/src/model/date.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'upsert_guard_profile_request.g.dart';

/// All fields optional — a guard fills the profile across an onboarding flow.
///
/// Properties:
/// * [fullName] - Guard full name (v1 parity).
/// * [gender] 
/// * [dateOfBirth] - ISO YYYY-MM-DD.
/// * [yearsOfExperience] 
/// * [previousWorkplace] 
/// * [bankName] 
/// * [accountNumber] - Stored in full; masked on owner reads (PDPA).
/// * [accountName] 
/// * [address] - Home address (v1 parity).
/// * [emergencyContactName] 
/// * [emergencyContactPhone] - Thai national format (≥10 digits, leading 0).
/// * [emergencyContactRelationship] 
@BuiltValue()
abstract class UpsertGuardProfileRequest implements Built<UpsertGuardProfileRequest, UpsertGuardProfileRequestBuilder> {
  /// Guard full name (v1 parity).
  @BuiltValueField(wireName: r'full_name')
  String? get fullName;

  @BuiltValueField(wireName: r'gender')
  String? get gender;

  /// ISO YYYY-MM-DD.
  @BuiltValueField(wireName: r'date_of_birth')
  Date? get dateOfBirth;

  @BuiltValueField(wireName: r'years_of_experience')
  int? get yearsOfExperience;

  @BuiltValueField(wireName: r'previous_workplace')
  String? get previousWorkplace;

  @BuiltValueField(wireName: r'bank_name')
  String? get bankName;

  /// Stored in full; masked on owner reads (PDPA).
  @BuiltValueField(wireName: r'account_number')
  String? get accountNumber;

  @BuiltValueField(wireName: r'account_name')
  String? get accountName;

  /// Home address (v1 parity).
  @BuiltValueField(wireName: r'address')
  String? get address;

  @BuiltValueField(wireName: r'emergency_contact_name')
  String? get emergencyContactName;

  /// Thai national format (≥10 digits, leading 0).
  @BuiltValueField(wireName: r'emergency_contact_phone')
  String? get emergencyContactPhone;

  @BuiltValueField(wireName: r'emergency_contact_relationship')
  String? get emergencyContactRelationship;

  UpsertGuardProfileRequest._();

  factory UpsertGuardProfileRequest([void updates(UpsertGuardProfileRequestBuilder b)]) = _$UpsertGuardProfileRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(UpsertGuardProfileRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<UpsertGuardProfileRequest> get serializer => _$UpsertGuardProfileRequestSerializer();
}

class _$UpsertGuardProfileRequestSerializer implements PrimitiveSerializer<UpsertGuardProfileRequest> {
  @override
  final Iterable<Type> types = const [UpsertGuardProfileRequest, _$UpsertGuardProfileRequest];

  @override
  final String wireName = r'UpsertGuardProfileRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    UpsertGuardProfileRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
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
  }

  @override
  Object serialize(
    Serializers serializers,
    UpsertGuardProfileRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required UpsertGuardProfileRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
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
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  UpsertGuardProfileRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = UpsertGuardProfileRequestBuilder();
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

