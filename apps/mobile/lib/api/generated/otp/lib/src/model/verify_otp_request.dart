//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'verify_otp_request.g.dart';

/// VerifyOtpRequest
///
/// Properties:
/// * [phone] 
/// * [code] - The OTP code (digits)
/// * [purpose] - Cross-check of the flow BOUND at `POST /otp/request` — the issued token's purpose comes from the stored code, never from this field. Omitted → `phone_verify` (registration). `pin_reset` → forgot-PIN reset; `phone_change` → change login phone. A mismatch with the stored code burns the code and fails generically.
@BuiltValue()
abstract class VerifyOtpRequest implements Built<VerifyOtpRequest, VerifyOtpRequestBuilder> {
  @BuiltValueField(wireName: r'phone')
  String get phone;

  /// The OTP code (digits)
  @BuiltValueField(wireName: r'code')
  String get code;

  /// Cross-check of the flow BOUND at `POST /otp/request` — the issued token's purpose comes from the stored code, never from this field. Omitted → `phone_verify` (registration). `pin_reset` → forgot-PIN reset; `phone_change` → change login phone. A mismatch with the stored code burns the code and fails generically.
  @BuiltValueField(wireName: r'purpose')
  VerifyOtpRequestPurposeEnum? get purpose;
  // enum purposeEnum {  phone_verify,  pin_reset,  phone_change,  };

  VerifyOtpRequest._();

  factory VerifyOtpRequest([void updates(VerifyOtpRequestBuilder b)]) = _$VerifyOtpRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(VerifyOtpRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<VerifyOtpRequest> get serializer => _$VerifyOtpRequestSerializer();
}

class _$VerifyOtpRequestSerializer implements PrimitiveSerializer<VerifyOtpRequest> {
  @override
  final Iterable<Type> types = const [VerifyOtpRequest, _$VerifyOtpRequest];

  @override
  final String wireName = r'VerifyOtpRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    VerifyOtpRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'phone';
    yield serializers.serialize(
      object.phone,
      specifiedType: const FullType(String),
    );
    yield r'code';
    yield serializers.serialize(
      object.code,
      specifiedType: const FullType(String),
    );
    if (object.purpose != null) {
      yield r'purpose';
      yield serializers.serialize(
        object.purpose,
        specifiedType: const FullType(VerifyOtpRequestPurposeEnum),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    VerifyOtpRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required VerifyOtpRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'phone':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.phone = valueDes;
          break;
        case r'code':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.code = valueDes;
          break;
        case r'purpose':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(VerifyOtpRequestPurposeEnum),
          ) as VerifyOtpRequestPurposeEnum;
          result.purpose = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  VerifyOtpRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = VerifyOtpRequestBuilder();
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

class VerifyOtpRequestPurposeEnum extends EnumClass {

  /// Cross-check of the flow BOUND at `POST /otp/request` — the issued token's purpose comes from the stored code, never from this field. Omitted → `phone_verify` (registration). `pin_reset` → forgot-PIN reset; `phone_change` → change login phone. A mismatch with the stored code burns the code and fails generically.
  @BuiltValueEnumConst(wireName: r'phone_verify')
  static const VerifyOtpRequestPurposeEnum phoneVerify = _$verifyOtpRequestPurposeEnum_phoneVerify;
  /// Cross-check of the flow BOUND at `POST /otp/request` — the issued token's purpose comes from the stored code, never from this field. Omitted → `phone_verify` (registration). `pin_reset` → forgot-PIN reset; `phone_change` → change login phone. A mismatch with the stored code burns the code and fails generically.
  @BuiltValueEnumConst(wireName: r'pin_reset')
  static const VerifyOtpRequestPurposeEnum pinReset = _$verifyOtpRequestPurposeEnum_pinReset;
  /// Cross-check of the flow BOUND at `POST /otp/request` — the issued token's purpose comes from the stored code, never from this field. Omitted → `phone_verify` (registration). `pin_reset` → forgot-PIN reset; `phone_change` → change login phone. A mismatch with the stored code burns the code and fails generically.
  @BuiltValueEnumConst(wireName: r'phone_change')
  static const VerifyOtpRequestPurposeEnum phoneChange = _$verifyOtpRequestPurposeEnum_phoneChange;

  static Serializer<VerifyOtpRequestPurposeEnum> get serializer => _$verifyOtpRequestPurposeEnumSerializer;

  const VerifyOtpRequestPurposeEnum._(String name): super(name);

  static BuiltSet<VerifyOtpRequestPurposeEnum> get values => _$verifyOtpRequestPurposeEnumValues;
  static VerifyOtpRequestPurposeEnum valueOf(String name) => _$verifyOtpRequestPurposeEnumValueOf(name);
}

