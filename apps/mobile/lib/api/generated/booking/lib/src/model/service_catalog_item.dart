//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'service_catalog_item.g.dart';

/// ServiceCatalogItem
///
/// Properties:
/// * [id] 
/// * [nameTh] 
/// * [nameEn] 
/// * [baseFee] - Base fee in THB per hour per guard (exact decimal string). VAT-EXCLUSIVE — the customer's bill adds VAT 7% on top (see payment `subtotal`/`vat_amount`/`grand_total`).
/// * [minHours] 
/// * [commissionPercent] - The platform's cut, as a PERCENT (0–100, exact decimal string; `\"10.00\"` = 10%). Deducted from the GUARD's pay, NOT added to the customer's bill: the customer pays the same either way, the guard receives `base_fee × actual_hours` minus this percent. `\"0.00\"` = the guard keeps everything.
/// * [cancellationFee] - Flat fee in THB (exact decimal string, ≥ 0) charged to the CUSTOMER when they cancel before work starts. Capped at what was actually paid (`min(fee, amount_paid)`), so an unpaid booking is never left owing anything. NOT charged when the guard withdraws — that is a full refund. `\"0.00\"` = free cancellation.
/// * [notes] 
/// * [isActive] 
/// * [createdAt] 
/// * [updatedAt] 
@BuiltValue()
abstract class ServiceCatalogItem implements Built<ServiceCatalogItem, ServiceCatalogItemBuilder> {
  @BuiltValueField(wireName: r'id')
  String get id;

  @BuiltValueField(wireName: r'name_th')
  String get nameTh;

  @BuiltValueField(wireName: r'name_en')
  String get nameEn;

  /// Base fee in THB per hour per guard (exact decimal string). VAT-EXCLUSIVE — the customer's bill adds VAT 7% on top (see payment `subtotal`/`vat_amount`/`grand_total`).
  @BuiltValueField(wireName: r'base_fee')
  String get baseFee;

  @BuiltValueField(wireName: r'min_hours')
  int get minHours;

  /// The platform's cut, as a PERCENT (0–100, exact decimal string; `\"10.00\"` = 10%). Deducted from the GUARD's pay, NOT added to the customer's bill: the customer pays the same either way, the guard receives `base_fee × actual_hours` minus this percent. `\"0.00\"` = the guard keeps everything.
  @BuiltValueField(wireName: r'commission_percent')
  String get commissionPercent;

  /// Flat fee in THB (exact decimal string, ≥ 0) charged to the CUSTOMER when they cancel before work starts. Capped at what was actually paid (`min(fee, amount_paid)`), so an unpaid booking is never left owing anything. NOT charged when the guard withdraws — that is a full refund. `\"0.00\"` = free cancellation.
  @BuiltValueField(wireName: r'cancellation_fee')
  String get cancellationFee;

  @BuiltValueField(wireName: r'notes')
  String? get notes;

  @BuiltValueField(wireName: r'is_active')
  bool get isActive;

  @BuiltValueField(wireName: r'created_at')
  DateTime get createdAt;

  @BuiltValueField(wireName: r'updated_at')
  DateTime get updatedAt;

  ServiceCatalogItem._();

  factory ServiceCatalogItem([void updates(ServiceCatalogItemBuilder b)]) = _$ServiceCatalogItem;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ServiceCatalogItemBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ServiceCatalogItem> get serializer => _$ServiceCatalogItemSerializer();
}

class _$ServiceCatalogItemSerializer implements PrimitiveSerializer<ServiceCatalogItem> {
  @override
  final Iterable<Type> types = const [ServiceCatalogItem, _$ServiceCatalogItem];

  @override
  final String wireName = r'ServiceCatalogItem';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ServiceCatalogItem object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'id';
    yield serializers.serialize(
      object.id,
      specifiedType: const FullType(String),
    );
    yield r'name_th';
    yield serializers.serialize(
      object.nameTh,
      specifiedType: const FullType(String),
    );
    yield r'name_en';
    yield serializers.serialize(
      object.nameEn,
      specifiedType: const FullType(String),
    );
    yield r'base_fee';
    yield serializers.serialize(
      object.baseFee,
      specifiedType: const FullType(String),
    );
    yield r'min_hours';
    yield serializers.serialize(
      object.minHours,
      specifiedType: const FullType(int),
    );
    yield r'commission_percent';
    yield serializers.serialize(
      object.commissionPercent,
      specifiedType: const FullType(String),
    );
    yield r'cancellation_fee';
    yield serializers.serialize(
      object.cancellationFee,
      specifiedType: const FullType(String),
    );
    if (object.notes != null) {
      yield r'notes';
      yield serializers.serialize(
        object.notes,
        specifiedType: const FullType(String),
      );
    }
    yield r'is_active';
    yield serializers.serialize(
      object.isActive,
      specifiedType: const FullType(bool),
    );
    yield r'created_at';
    yield serializers.serialize(
      object.createdAt,
      specifiedType: const FullType(DateTime),
    );
    yield r'updated_at';
    yield serializers.serialize(
      object.updatedAt,
      specifiedType: const FullType(DateTime),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    ServiceCatalogItem object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ServiceCatalogItemBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.id = valueDes;
          break;
        case r'name_th':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.nameTh = valueDes;
          break;
        case r'name_en':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.nameEn = valueDes;
          break;
        case r'base_fee':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.baseFee = valueDes;
          break;
        case r'min_hours':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.minHours = valueDes;
          break;
        case r'commission_percent':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.commissionPercent = valueDes;
          break;
        case r'cancellation_fee':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.cancellationFee = valueDes;
          break;
        case r'notes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.notes = valueDes;
          break;
        case r'is_active':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(bool),
          ) as bool;
          result.isActive = valueDes;
          break;
        case r'created_at':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.createdAt = valueDes;
          break;
        case r'updated_at':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(DateTime),
          ) as DateTime;
          result.updatedAt = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ServiceCatalogItem deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ServiceCatalogItemBuilder();
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

