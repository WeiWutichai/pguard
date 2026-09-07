//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'update_guard_payout_request.g.dart';

/// The ADMIN payout-correction body for `PUT /admin/guard-profiles/{user_id}/payout`. All fields optional and **merge-semantic**: a field left ABSENT — or sent as `null` — keeps the stored value (the same convention as payment's `PUT /admin/payouts/config`). There is deliberately no way to CLEAR a field here. 
///
/// Properties:
/// * [taxId] - Thai national/tax id — the PromptPay NAT proxy + the ภ.ง.ด. recipient TIN, i.e. the one value that makes a guard payable.  **Validation (GUARD rule):** 8–20 digits with spaces/hyphens allowed, PLUS a length-conditional Thai national-id **mod-11 checksum** — a value of EXACTLY 13 digits must pass it (400 otherwise, with Thai copy naming PromptPay); 8–12 and 14–20 digits are shape-only. This endpoint writes the account the payout file CREDITS, and PromptPay is irreversible, so a mistyped-but-well-shaped 13-digit id is rejected rather than paid. Identical to the guard rule on `UpsertGuardProfileRequest`, and deliberately STRICTER than the company tax id on `UpdateOrgSettingsRequest`.  Also rejected with 400 if it still carries the read-time mask (`*`), since that can only be a client re-PUTting what it displayed. 
/// * [bankName] 
/// * [accountNumber] - Rejected with 400 if it still carries the read-time mask (`*`).
/// * [accountName] 
@BuiltValue()
abstract class UpdateGuardPayoutRequest implements Built<UpdateGuardPayoutRequest, UpdateGuardPayoutRequestBuilder> {
  /// Thai national/tax id — the PromptPay NAT proxy + the ภ.ง.ด. recipient TIN, i.e. the one value that makes a guard payable.  **Validation (GUARD rule):** 8–20 digits with spaces/hyphens allowed, PLUS a length-conditional Thai national-id **mod-11 checksum** — a value of EXACTLY 13 digits must pass it (400 otherwise, with Thai copy naming PromptPay); 8–12 and 14–20 digits are shape-only. This endpoint writes the account the payout file CREDITS, and PromptPay is irreversible, so a mistyped-but-well-shaped 13-digit id is rejected rather than paid. Identical to the guard rule on `UpsertGuardProfileRequest`, and deliberately STRICTER than the company tax id on `UpdateOrgSettingsRequest`.  Also rejected with 400 if it still carries the read-time mask (`*`), since that can only be a client re-PUTting what it displayed. 
  @BuiltValueField(wireName: r'tax_id')
  String? get taxId;

  @BuiltValueField(wireName: r'bank_name')
  String? get bankName;

  /// Rejected with 400 if it still carries the read-time mask (`*`).
  @BuiltValueField(wireName: r'account_number')
  String? get accountNumber;

  @BuiltValueField(wireName: r'account_name')
  String? get accountName;

  UpdateGuardPayoutRequest._();

  factory UpdateGuardPayoutRequest([void updates(UpdateGuardPayoutRequestBuilder b)]) = _$UpdateGuardPayoutRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(UpdateGuardPayoutRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<UpdateGuardPayoutRequest> get serializer => _$UpdateGuardPayoutRequestSerializer();
}

class _$UpdateGuardPayoutRequestSerializer implements PrimitiveSerializer<UpdateGuardPayoutRequest> {
  @override
  final Iterable<Type> types = const [UpdateGuardPayoutRequest, _$UpdateGuardPayoutRequest];

  @override
  final String wireName = r'UpdateGuardPayoutRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    UpdateGuardPayoutRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.taxId != null) {
      yield r'tax_id';
      yield serializers.serialize(
        object.taxId,
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
  }

  @override
  Object serialize(
    Serializers serializers,
    UpdateGuardPayoutRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required UpdateGuardPayoutRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'tax_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.taxId = valueDes;
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
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  UpdateGuardPayoutRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = UpdateGuardPayoutRequestBuilder();
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

