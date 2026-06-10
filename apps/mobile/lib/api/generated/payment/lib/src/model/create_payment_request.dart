//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'create_payment_request.g.dart';

/// CreatePaymentRequest
///
/// Properties:
/// * [bookingId] 
/// * [amount] - Exact decimal amount as a string (e.g. \"400.00\") to avoid float rounding. Validated `> 0`, `<= cap`, ≤2dp, AND must cover the server-computed `expected_total` (the client can never undercut the price; surplus = extra tip). 
/// * [paymentMethod] 
@BuiltValue()
abstract class CreatePaymentRequest implements Built<CreatePaymentRequest, CreatePaymentRequestBuilder> {
  @BuiltValueField(wireName: r'booking_id')
  String get bookingId;

  /// Exact decimal amount as a string (e.g. \"400.00\") to avoid float rounding. Validated `> 0`, `<= cap`, ≤2dp, AND must cover the server-computed `expected_total` (the client can never undercut the price; surplus = extra tip). 
  @BuiltValueField(wireName: r'amount')
  String get amount;

  @BuiltValueField(wireName: r'payment_method')
  CreatePaymentRequestPaymentMethodEnum get paymentMethod;
  // enum paymentMethodEnum {  promptpay,  credit_card,  debit_card,  mobile_banking,  };

  CreatePaymentRequest._();

  factory CreatePaymentRequest([void updates(CreatePaymentRequestBuilder b)]) = _$CreatePaymentRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(CreatePaymentRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<CreatePaymentRequest> get serializer => _$CreatePaymentRequestSerializer();
}

class _$CreatePaymentRequestSerializer implements PrimitiveSerializer<CreatePaymentRequest> {
  @override
  final Iterable<Type> types = const [CreatePaymentRequest, _$CreatePaymentRequest];

  @override
  final String wireName = r'CreatePaymentRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    CreatePaymentRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'booking_id';
    yield serializers.serialize(
      object.bookingId,
      specifiedType: const FullType(String),
    );
    yield r'amount';
    yield serializers.serialize(
      object.amount,
      specifiedType: const FullType(String),
    );
    yield r'payment_method';
    yield serializers.serialize(
      object.paymentMethod,
      specifiedType: const FullType(CreatePaymentRequestPaymentMethodEnum),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    CreatePaymentRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required CreatePaymentRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'booking_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.bookingId = valueDes;
          break;
        case r'amount':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.amount = valueDes;
          break;
        case r'payment_method':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(CreatePaymentRequestPaymentMethodEnum),
          ) as CreatePaymentRequestPaymentMethodEnum;
          result.paymentMethod = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  CreatePaymentRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = CreatePaymentRequestBuilder();
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

class CreatePaymentRequestPaymentMethodEnum extends EnumClass {

  @BuiltValueEnumConst(wireName: r'promptpay')
  static const CreatePaymentRequestPaymentMethodEnum promptpay = _$createPaymentRequestPaymentMethodEnum_promptpay;
  @BuiltValueEnumConst(wireName: r'credit_card')
  static const CreatePaymentRequestPaymentMethodEnum creditCard = _$createPaymentRequestPaymentMethodEnum_creditCard;
  @BuiltValueEnumConst(wireName: r'debit_card')
  static const CreatePaymentRequestPaymentMethodEnum debitCard = _$createPaymentRequestPaymentMethodEnum_debitCard;
  @BuiltValueEnumConst(wireName: r'mobile_banking')
  static const CreatePaymentRequestPaymentMethodEnum mobileBanking = _$createPaymentRequestPaymentMethodEnum_mobileBanking;

  static Serializer<CreatePaymentRequestPaymentMethodEnum> get serializer => _$createPaymentRequestPaymentMethodEnumSerializer;

  const CreatePaymentRequestPaymentMethodEnum._(String name): super(name);

  static BuiltSet<CreatePaymentRequestPaymentMethodEnum> get values => _$createPaymentRequestPaymentMethodEnumValues;
  static CreatePaymentRequestPaymentMethodEnum valueOf(String name) => _$createPaymentRequestPaymentMethodEnumValueOf(name);
}

