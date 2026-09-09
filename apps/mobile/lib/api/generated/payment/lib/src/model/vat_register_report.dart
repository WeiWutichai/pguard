//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:pguard_payment_api/src/model/vat_register_row.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'vat_register_report.g.dart';

/// VatRegisterReport
///
/// Properties:
/// * [month] 
/// * [rows] 
/// * [rowCount] 
/// * [totalSubtotal] 
/// * [totalVat] - The figure transcribed onto the ภ.พ.30.
/// * [totalAmount] 
@BuiltValue()
abstract class VatRegisterReport implements Built<VatRegisterReport, VatRegisterReportBuilder> {
  @BuiltValueField(wireName: r'month')
  String get month;

  @BuiltValueField(wireName: r'rows')
  BuiltList<VatRegisterRow> get rows;

  @BuiltValueField(wireName: r'row_count')
  int get rowCount;

  @BuiltValueField(wireName: r'total_subtotal')
  String get totalSubtotal;

  /// The figure transcribed onto the ภ.พ.30.
  @BuiltValueField(wireName: r'total_vat')
  String get totalVat;

  @BuiltValueField(wireName: r'total_amount')
  String get totalAmount;

  VatRegisterReport._();

  factory VatRegisterReport([void updates(VatRegisterReportBuilder b)]) = _$VatRegisterReport;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(VatRegisterReportBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<VatRegisterReport> get serializer => _$VatRegisterReportSerializer();
}

class _$VatRegisterReportSerializer implements PrimitiveSerializer<VatRegisterReport> {
  @override
  final Iterable<Type> types = const [VatRegisterReport, _$VatRegisterReport];

  @override
  final String wireName = r'VatRegisterReport';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    VatRegisterReport object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'month';
    yield serializers.serialize(
      object.month,
      specifiedType: const FullType(String),
    );
    yield r'rows';
    yield serializers.serialize(
      object.rows,
      specifiedType: const FullType(BuiltList, [FullType(VatRegisterRow)]),
    );
    yield r'row_count';
    yield serializers.serialize(
      object.rowCount,
      specifiedType: const FullType(int),
    );
    yield r'total_subtotal';
    yield serializers.serialize(
      object.totalSubtotal,
      specifiedType: const FullType(String),
    );
    yield r'total_vat';
    yield serializers.serialize(
      object.totalVat,
      specifiedType: const FullType(String),
    );
    yield r'total_amount';
    yield serializers.serialize(
      object.totalAmount,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    VatRegisterReport object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required VatRegisterReportBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'month':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.month = valueDes;
          break;
        case r'rows':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(VatRegisterRow)]),
          ) as BuiltList<VatRegisterRow>;
          result.rows.replace(valueDes);
          break;
        case r'row_count':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.rowCount = valueDes;
          break;
        case r'total_subtotal':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.totalSubtotal = valueDes;
          break;
        case r'total_vat':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.totalVat = valueDes;
          break;
        case r'total_amount':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.totalAmount = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  VatRegisterReport deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = VatRegisterReportBuilder();
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

