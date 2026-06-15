//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:pguard_payment_api/src/model/revenue_point.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'revenue_report.g.dart';

/// RevenueReport
///
/// Properties:
/// * [series] 
/// * [total] - Net revenue over the window (decimal string).
/// * [prevTotal] - Net revenue over the prior equal-length window.
/// * [momPct] - Month-over-month % vs the prior window (null when it had zero revenue).
@BuiltValue()
abstract class RevenueReport implements Built<RevenueReport, RevenueReportBuilder> {
  @BuiltValueField(wireName: r'series')
  BuiltList<RevenuePoint> get series;

  /// Net revenue over the window (decimal string).
  @BuiltValueField(wireName: r'total')
  String get total;

  /// Net revenue over the prior equal-length window.
  @BuiltValueField(wireName: r'prev_total')
  String get prevTotal;

  /// Month-over-month % vs the prior window (null when it had zero revenue).
  @BuiltValueField(wireName: r'mom_pct')
  double? get momPct;

  RevenueReport._();

  factory RevenueReport([void updates(RevenueReportBuilder b)]) = _$RevenueReport;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(RevenueReportBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<RevenueReport> get serializer => _$RevenueReportSerializer();
}

class _$RevenueReportSerializer implements PrimitiveSerializer<RevenueReport> {
  @override
  final Iterable<Type> types = const [RevenueReport, _$RevenueReport];

  @override
  final String wireName = r'RevenueReport';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    RevenueReport object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'series';
    yield serializers.serialize(
      object.series,
      specifiedType: const FullType(BuiltList, [FullType(RevenuePoint)]),
    );
    yield r'total';
    yield serializers.serialize(
      object.total,
      specifiedType: const FullType(String),
    );
    yield r'prev_total';
    yield serializers.serialize(
      object.prevTotal,
      specifiedType: const FullType(String),
    );
    if (object.momPct != null) {
      yield r'mom_pct';
      yield serializers.serialize(
        object.momPct,
        specifiedType: const FullType(double),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    RevenueReport object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required RevenueReportBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'series':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(RevenuePoint)]),
          ) as BuiltList<RevenuePoint>;
          result.series.replace(valueDes);
          break;
        case r'total':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.total = valueDes;
          break;
        case r'prev_total':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.prevTotal = valueDes;
          break;
        case r'mom_pct':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(double),
          ) as double;
          result.momPct = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  RevenueReport deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = RevenueReportBuilder();
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

