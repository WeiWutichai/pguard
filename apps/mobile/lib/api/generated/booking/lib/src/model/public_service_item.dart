//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'public_service_item.g.dart';

/// The customer-facing view of an ACTIVE catalog service (the `GET /services` picker) — a narrow subset of `ServiceCatalogItem` (no `is_active`/timestamps). `notes` is surfaced as the customer-facing package description. Neither money knob is exposed here. `commission_percent` never will be: it only changes what the GUARD is paid, never what the customer pays, so it is not the customer's business. `cancellation_fee` IS the customer's business but is not served yet — today the customer only learns it from their own booking's `cancellation_fee` snapshot after creation. Surfacing it on this picker (pre-booking disclosure) is a known gap.
///
/// Properties:
/// * [id] 
/// * [nameTh] 
/// * [nameEn] 
/// * [baseFee] - Server-owned ฿/hour/guard rate (exact decimal string). VAT-EXCLUSIVE — VAT 7% is added on top at checkout, so the amount charged is higher than base_fee × hours.
/// * [minHours] 
/// * [notes] - Short customer-facing package description (the admin notes).
@BuiltValue()
abstract class PublicServiceItem implements Built<PublicServiceItem, PublicServiceItemBuilder> {
  @BuiltValueField(wireName: r'id')
  String get id;

  @BuiltValueField(wireName: r'name_th')
  String get nameTh;

  @BuiltValueField(wireName: r'name_en')
  String get nameEn;

  /// Server-owned ฿/hour/guard rate (exact decimal string). VAT-EXCLUSIVE — VAT 7% is added on top at checkout, so the amount charged is higher than base_fee × hours.
  @BuiltValueField(wireName: r'base_fee')
  String get baseFee;

  @BuiltValueField(wireName: r'min_hours')
  int get minHours;

  /// Short customer-facing package description (the admin notes).
  @BuiltValueField(wireName: r'notes')
  String? get notes;

  PublicServiceItem._();

  factory PublicServiceItem([void updates(PublicServiceItemBuilder b)]) = _$PublicServiceItem;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(PublicServiceItemBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<PublicServiceItem> get serializer => _$PublicServiceItemSerializer();
}

class _$PublicServiceItemSerializer implements PrimitiveSerializer<PublicServiceItem> {
  @override
  final Iterable<Type> types = const [PublicServiceItem, _$PublicServiceItem];

  @override
  final String wireName = r'PublicServiceItem';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    PublicServiceItem object, {
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
    if (object.notes != null) {
      yield r'notes';
      yield serializers.serialize(
        object.notes,
        specifiedType: const FullType(String),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    PublicServiceItem object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required PublicServiceItemBuilder result,
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
        case r'notes':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.notes = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  PublicServiceItem deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = PublicServiceItemBuilder();
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

