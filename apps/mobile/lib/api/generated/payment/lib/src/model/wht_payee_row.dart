//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'wht_payee_row.g.dart';

/// One payee of the ภ.ง.ด.3/53 filing, summed over every LIVE payout item in the period whose batch actually moved money (`generated`/`uploaded`/`confirmed`). A `rejected` batch — the bank refused the file — and a `voided` one withheld nothing and are both excluded. 
///
/// Properties:
/// * [guardId] 
/// * [taxId] - The payee's TIN, reported AS STORED (a report is the wrong place to silently reshape an identifier that goes onto a government form). `null` when profile has no id on file — the row is still reported, because the money WAS withheld and the filing has to account for it. 
/// * [name] 
/// * [address] 
/// * [jobCount] 
/// * [income] - Gross assessable income paid (exact decimal, string).
/// * [wht] - Tax withheld — the figure the law requires us to report.
@BuiltValue()
abstract class WhtPayeeRow implements Built<WhtPayeeRow, WhtPayeeRowBuilder> {
  @BuiltValueField(wireName: r'guard_id')
  String get guardId;

  /// The payee's TIN, reported AS STORED (a report is the wrong place to silently reshape an identifier that goes onto a government form). `null` when profile has no id on file — the row is still reported, because the money WAS withheld and the filing has to account for it. 
  @BuiltValueField(wireName: r'tax_id')
  String? get taxId;

  @BuiltValueField(wireName: r'name')
  String? get name;

  @BuiltValueField(wireName: r'address')
  String? get address;

  @BuiltValueField(wireName: r'job_count')
  int get jobCount;

  /// Gross assessable income paid (exact decimal, string).
  @BuiltValueField(wireName: r'income')
  String get income;

  /// Tax withheld — the figure the law requires us to report.
  @BuiltValueField(wireName: r'wht')
  String get wht;

  WhtPayeeRow._();

  factory WhtPayeeRow([void updates(WhtPayeeRowBuilder b)]) = _$WhtPayeeRow;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(WhtPayeeRowBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<WhtPayeeRow> get serializer => _$WhtPayeeRowSerializer();
}

class _$WhtPayeeRowSerializer implements PrimitiveSerializer<WhtPayeeRow> {
  @override
  final Iterable<Type> types = const [WhtPayeeRow, _$WhtPayeeRow];

  @override
  final String wireName = r'WhtPayeeRow';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    WhtPayeeRow object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'guard_id';
    yield serializers.serialize(
      object.guardId,
      specifiedType: const FullType(String),
    );
    if (object.taxId != null) {
      yield r'tax_id';
      yield serializers.serialize(
        object.taxId,
        specifiedType: const FullType(String),
      );
    }
    if (object.name != null) {
      yield r'name';
      yield serializers.serialize(
        object.name,
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
    yield r'job_count';
    yield serializers.serialize(
      object.jobCount,
      specifiedType: const FullType(int),
    );
    yield r'income';
    yield serializers.serialize(
      object.income,
      specifiedType: const FullType(String),
    );
    yield r'wht';
    yield serializers.serialize(
      object.wht,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    WhtPayeeRow object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required WhtPayeeRowBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'guard_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.guardId = valueDes;
          break;
        case r'tax_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.taxId = valueDes;
          break;
        case r'name':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.name = valueDes;
          break;
        case r'address':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.address = valueDes;
          break;
        case r'job_count':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.jobCount = valueDes;
          break;
        case r'income':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.income = valueDes;
          break;
        case r'wht':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.wht = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  WhtPayeeRow deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = WhtPayeeRowBuilder();
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

