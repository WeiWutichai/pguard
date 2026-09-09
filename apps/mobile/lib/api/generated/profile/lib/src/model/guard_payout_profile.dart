//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'guard_payout_profile.g.dart';

/// Guard payout destination + ภ.ง.ด.53 recipient block, returned ONLY by `GET /internal/guards/{guard_id}/payout-profile` (service-JWT). Every field is nullable because the underlying columns are — payment decides what a missing value means for its own file rather than this service guessing. 
///
/// Properties:
/// * [fullName] - The SCB recipient-name column; null when onboarding never captured it.
/// * [taxId] - The **UNMASKED** Thai national/tax id — the PromptPay `NAT` proxy (13 digits) money is credited to AND the ภ.ง.ด.53 recipient TIN. This is the ONLY endpoint that returns it in the clear; every owner/admin profile read masks it to the last 4 (PDPA). `null` when the guard has none on file, in which case `phone` is the `MOB` fallback. 
/// * [address] - Recipient address lines of the ภ.ง.ด.53 block.
/// * [phone] - The guard's LOGIN phone from identity — the PromptPay `MOB` fallback proxy (10 digits) used when `tax_id` is null. **BEST-EFFORT: `null` on an identity outage, never an error** (the read still 200s). NOT `emergency_contact_phone`, which is someone else's number and must never be paid to. Returned RAW; the caller normalises. 
@BuiltValue()
abstract class GuardPayoutProfile implements Built<GuardPayoutProfile, GuardPayoutProfileBuilder> {
  /// The SCB recipient-name column; null when onboarding never captured it.
  @BuiltValueField(wireName: r'full_name')
  String? get fullName;

  /// The **UNMASKED** Thai national/tax id — the PromptPay `NAT` proxy (13 digits) money is credited to AND the ภ.ง.ด.53 recipient TIN. This is the ONLY endpoint that returns it in the clear; every owner/admin profile read masks it to the last 4 (PDPA). `null` when the guard has none on file, in which case `phone` is the `MOB` fallback. 
  @BuiltValueField(wireName: r'tax_id')
  String? get taxId;

  /// Recipient address lines of the ภ.ง.ด.53 block.
  @BuiltValueField(wireName: r'address')
  String? get address;

  /// The guard's LOGIN phone from identity — the PromptPay `MOB` fallback proxy (10 digits) used when `tax_id` is null. **BEST-EFFORT: `null` on an identity outage, never an error** (the read still 200s). NOT `emergency_contact_phone`, which is someone else's number and must never be paid to. Returned RAW; the caller normalises. 
  @BuiltValueField(wireName: r'phone')
  String? get phone;

  GuardPayoutProfile._();

  factory GuardPayoutProfile([void updates(GuardPayoutProfileBuilder b)]) = _$GuardPayoutProfile;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(GuardPayoutProfileBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<GuardPayoutProfile> get serializer => _$GuardPayoutProfileSerializer();
}

class _$GuardPayoutProfileSerializer implements PrimitiveSerializer<GuardPayoutProfile> {
  @override
  final Iterable<Type> types = const [GuardPayoutProfile, _$GuardPayoutProfile];

  @override
  final String wireName = r'GuardPayoutProfile';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    GuardPayoutProfile object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.fullName != null) {
      yield r'full_name';
      yield serializers.serialize(
        object.fullName,
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
    if (object.phone != null) {
      yield r'phone';
      yield serializers.serialize(
        object.phone,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    GuardPayoutProfile object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required GuardPayoutProfileBuilder result,
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
        case r'phone':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.phone = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  GuardPayoutProfile deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = GuardPayoutProfileBuilder();
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

