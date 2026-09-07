//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:pguard_payment_api/src/model/wht_payee_row.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'wht_payee_report.g.dart';

/// WhtPayeeReport
///
/// Properties:
/// * [month] 
/// * [formTypeCode] - From the stored payout config, reported EXACTLY as stored — `53` = ภ.ง.ด.53 (juristic person), `04` = ภ.ง.ด.3 (individual). Which form applies is the operator's TAX decision; a report that silently corrected it would be filing something other than what was certified to the payee. 
/// * [incomeTypeCode] 
/// * [incomeDescription] 
/// * [rows] 
/// * [payeeCount] 
/// * [totalIncome] 
/// * [totalWht] 
@BuiltValue()
abstract class WhtPayeeReport implements Built<WhtPayeeReport, WhtPayeeReportBuilder> {
  @BuiltValueField(wireName: r'month')
  String get month;

  /// From the stored payout config, reported EXACTLY as stored — `53` = ภ.ง.ด.53 (juristic person), `04` = ภ.ง.ด.3 (individual). Which form applies is the operator's TAX decision; a report that silently corrected it would be filing something other than what was certified to the payee. 
  @BuiltValueField(wireName: r'form_type_code')
  String get formTypeCode;

  @BuiltValueField(wireName: r'income_type_code')
  String get incomeTypeCode;

  @BuiltValueField(wireName: r'income_description')
  String get incomeDescription;

  @BuiltValueField(wireName: r'rows')
  BuiltList<WhtPayeeRow> get rows;

  @BuiltValueField(wireName: r'payee_count')
  int get payeeCount;

  @BuiltValueField(wireName: r'total_income')
  String get totalIncome;

  @BuiltValueField(wireName: r'total_wht')
  String get totalWht;

  WhtPayeeReport._();

  factory WhtPayeeReport([void updates(WhtPayeeReportBuilder b)]) = _$WhtPayeeReport;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(WhtPayeeReportBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<WhtPayeeReport> get serializer => _$WhtPayeeReportSerializer();
}

class _$WhtPayeeReportSerializer implements PrimitiveSerializer<WhtPayeeReport> {
  @override
  final Iterable<Type> types = const [WhtPayeeReport, _$WhtPayeeReport];

  @override
  final String wireName = r'WhtPayeeReport';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    WhtPayeeReport object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'month';
    yield serializers.serialize(
      object.month,
      specifiedType: const FullType(String),
    );
    yield r'form_type_code';
    yield serializers.serialize(
      object.formTypeCode,
      specifiedType: const FullType(String),
    );
    yield r'income_type_code';
    yield serializers.serialize(
      object.incomeTypeCode,
      specifiedType: const FullType(String),
    );
    yield r'income_description';
    yield serializers.serialize(
      object.incomeDescription,
      specifiedType: const FullType(String),
    );
    yield r'rows';
    yield serializers.serialize(
      object.rows,
      specifiedType: const FullType(BuiltList, [FullType(WhtPayeeRow)]),
    );
    yield r'payee_count';
    yield serializers.serialize(
      object.payeeCount,
      specifiedType: const FullType(int),
    );
    yield r'total_income';
    yield serializers.serialize(
      object.totalIncome,
      specifiedType: const FullType(String),
    );
    yield r'total_wht';
    yield serializers.serialize(
      object.totalWht,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    WhtPayeeReport object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required WhtPayeeReportBuilder result,
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
        case r'form_type_code':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.formTypeCode = valueDes;
          break;
        case r'income_type_code':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.incomeTypeCode = valueDes;
          break;
        case r'income_description':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.incomeDescription = valueDes;
          break;
        case r'rows':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(WhtPayeeRow)]),
          ) as BuiltList<WhtPayeeRow>;
          result.rows.replace(valueDes);
          break;
        case r'payee_count':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.payeeCount = valueDes;
          break;
        case r'total_income':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.totalIncome = valueDes;
          break;
        case r'total_wht':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.totalWht = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  WhtPayeeReport deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = WhtPayeeReportBuilder();
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

