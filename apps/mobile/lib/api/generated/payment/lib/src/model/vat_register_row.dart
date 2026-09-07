//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_payment_api/src/model/date.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'vat_register_row.g.dart';

/// One line of the output-VAT register — one settled payment.
///
/// Properties:
/// * [date] - The Bangkok day the customer PAID — the VAT tax point for a service.
/// * [paymentId] 
/// * [bookingId] 
/// * [customerId] - Resolve names in bulk via `POST /admin/users/resolve` — this report does not fan out per row.
/// * [subtotal] - The VAT-EXCLUSIVE settled bill (exact decimal, string).
/// * [vat] - The VAT charged on it.
/// * [total] - `subtotal + vat` — what the tax invoice totals.
@BuiltValue()
abstract class VatRegisterRow implements Built<VatRegisterRow, VatRegisterRowBuilder> {
  /// The Bangkok day the customer PAID — the VAT tax point for a service.
  @BuiltValueField(wireName: r'date')
  Date get date;

  @BuiltValueField(wireName: r'payment_id')
  String get paymentId;

  @BuiltValueField(wireName: r'booking_id')
  String get bookingId;

  /// Resolve names in bulk via `POST /admin/users/resolve` — this report does not fan out per row.
  @BuiltValueField(wireName: r'customer_id')
  String get customerId;

  /// The VAT-EXCLUSIVE settled bill (exact decimal, string).
  @BuiltValueField(wireName: r'subtotal')
  String get subtotal;

  /// The VAT charged on it.
  @BuiltValueField(wireName: r'vat')
  String get vat;

  /// `subtotal + vat` — what the tax invoice totals.
  @BuiltValueField(wireName: r'total')
  String get total;

  VatRegisterRow._();

  factory VatRegisterRow([void updates(VatRegisterRowBuilder b)]) = _$VatRegisterRow;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(VatRegisterRowBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<VatRegisterRow> get serializer => _$VatRegisterRowSerializer();
}

class _$VatRegisterRowSerializer implements PrimitiveSerializer<VatRegisterRow> {
  @override
  final Iterable<Type> types = const [VatRegisterRow, _$VatRegisterRow];

  @override
  final String wireName = r'VatRegisterRow';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    VatRegisterRow object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'date';
    yield serializers.serialize(
      object.date,
      specifiedType: const FullType(Date),
    );
    yield r'payment_id';
    yield serializers.serialize(
      object.paymentId,
      specifiedType: const FullType(String),
    );
    yield r'booking_id';
    yield serializers.serialize(
      object.bookingId,
      specifiedType: const FullType(String),
    );
    yield r'customer_id';
    yield serializers.serialize(
      object.customerId,
      specifiedType: const FullType(String),
    );
    yield r'subtotal';
    yield serializers.serialize(
      object.subtotal,
      specifiedType: const FullType(String),
    );
    yield r'vat';
    yield serializers.serialize(
      object.vat,
      specifiedType: const FullType(String),
    );
    yield r'total';
    yield serializers.serialize(
      object.total,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    VatRegisterRow object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required VatRegisterRowBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'date':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(Date),
          ) as Date;
          result.date = valueDes;
          break;
        case r'payment_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.paymentId = valueDes;
          break;
        case r'booking_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.bookingId = valueDes;
          break;
        case r'customer_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.customerId = valueDes;
          break;
        case r'subtotal':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.subtotal = valueDes;
          break;
        case r'vat':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.vat = valueDes;
          break;
        case r'total':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.total = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  VatRegisterRow deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = VatRegisterRowBuilder();
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

