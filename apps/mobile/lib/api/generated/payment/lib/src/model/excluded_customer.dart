//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'excluded_customer.g.dart';

/// ExcludedCustomer
///
/// Properties:
/// * [customerId] 
/// * [reason] - Thai copy explaining why this customer cannot be refunded in this batch — no customer profile, no name for the mandatory recipient column, no usable PromptPay phone, or a total outside SCB's per-transaction bounds (the reason names the bound). Their obligations stay `pending`; nothing about them is marked processed. 
/// * [obligationCount] 
@BuiltValue()
abstract class ExcludedCustomer implements Built<ExcludedCustomer, ExcludedCustomerBuilder> {
  @BuiltValueField(wireName: r'customer_id')
  String get customerId;

  /// Thai copy explaining why this customer cannot be refunded in this batch — no customer profile, no name for the mandatory recipient column, no usable PromptPay phone, or a total outside SCB's per-transaction bounds (the reason names the bound). Their obligations stay `pending`; nothing about them is marked processed. 
  @BuiltValueField(wireName: r'reason')
  String get reason;

  @BuiltValueField(wireName: r'obligation_count')
  int get obligationCount;

  ExcludedCustomer._();

  factory ExcludedCustomer([void updates(ExcludedCustomerBuilder b)]) = _$ExcludedCustomer;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ExcludedCustomerBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ExcludedCustomer> get serializer => _$ExcludedCustomerSerializer();
}

class _$ExcludedCustomerSerializer implements PrimitiveSerializer<ExcludedCustomer> {
  @override
  final Iterable<Type> types = const [ExcludedCustomer, _$ExcludedCustomer];

  @override
  final String wireName = r'ExcludedCustomer';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ExcludedCustomer object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'customer_id';
    yield serializers.serialize(
      object.customerId,
      specifiedType: const FullType(String),
    );
    yield r'reason';
    yield serializers.serialize(
      object.reason,
      specifiedType: const FullType(String),
    );
    yield r'obligation_count';
    yield serializers.serialize(
      object.obligationCount,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    ExcludedCustomer object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ExcludedCustomerBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'customer_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.customerId = valueDes;
          break;
        case r'reason':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.reason = valueDes;
          break;
        case r'obligation_count':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.obligationCount = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ExcludedCustomer deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ExcludedCustomerBuilder();
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

