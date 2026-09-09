//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'customer_payout_profile.g.dart';

/// Customer REFUND destination, returned ONLY by `GET /internal/customers/{user_id}/payout-profile` (service-JWT). Deliberately NARROWER than `GuardPayoutProfile`: no `tax_id` at all, because a refund is the customer's own money coming back — no withholding, so no TIN to return or leak. 
///
/// Properties:
/// * [fullName] - The SCB recipient-name column; null when registration never captured it.
/// * [phone] - The PromptPay `MOB` proxy (10 digits): `customer_profiles.contact_phone` when set, else the account's LOGIN phone from identity. **BEST-EFFORT: an identity outage degrades this to whatever the profile row holds (possibly `null`) and the read still 200s.** `null` means UNREFUNDABLE — exclude the customer, never substitute. Returned RAW; the caller normalises. 
/// * [address] 
@BuiltValue()
abstract class CustomerPayoutProfile implements Built<CustomerPayoutProfile, CustomerPayoutProfileBuilder> {
  /// The SCB recipient-name column; null when registration never captured it.
  @BuiltValueField(wireName: r'full_name')
  String? get fullName;

  /// The PromptPay `MOB` proxy (10 digits): `customer_profiles.contact_phone` when set, else the account's LOGIN phone from identity. **BEST-EFFORT: an identity outage degrades this to whatever the profile row holds (possibly `null`) and the read still 200s.** `null` means UNREFUNDABLE — exclude the customer, never substitute. Returned RAW; the caller normalises. 
  @BuiltValueField(wireName: r'phone')
  String? get phone;

  @BuiltValueField(wireName: r'address')
  String? get address;

  CustomerPayoutProfile._();

  factory CustomerPayoutProfile([void updates(CustomerPayoutProfileBuilder b)]) = _$CustomerPayoutProfile;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CustomerPayoutProfileBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<CustomerPayoutProfile> get serializer => _$CustomerPayoutProfileSerializer();
}

class _$CustomerPayoutProfileSerializer implements PrimitiveSerializer<CustomerPayoutProfile> {
  @override
  final Iterable<Type> types = const [CustomerPayoutProfile, _$CustomerPayoutProfile];

  @override
  final String wireName = r'CustomerPayoutProfile';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CustomerPayoutProfile object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.fullName != null) {
      yield r'full_name';
      yield serializers.serialize(
        object.fullName,
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
    if (object.address != null) {
      yield r'address';
      yield serializers.serialize(
        object.address,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    CustomerPayoutProfile object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required CustomerPayoutProfileBuilder result,
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
        case r'phone':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.phone = valueDes;
          break;
        case r'address':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.address = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  CustomerPayoutProfile deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CustomerPayoutProfileBuilder();
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

