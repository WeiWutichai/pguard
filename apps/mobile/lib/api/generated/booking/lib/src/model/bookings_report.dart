//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_booking_api/src/model/retention_point.dart';
import 'package:pguard_booking_api/src/model/daily_count.dart';
import 'package:built_collection/built_collection.dart';
import 'package:pguard_booking_api/src/model/utilization_cell.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'bookings_report.g.dart';

/// BookingsReport
///
/// Properties:
/// * [daily] 
/// * [utilization] 
/// * [retention] 
/// * [total] - Total bookings in the window.
@BuiltValue()
abstract class BookingsReport implements Built<BookingsReport, BookingsReportBuilder> {
  @BuiltValueField(wireName: r'daily')
  BuiltList<DailyCount> get daily;

  @BuiltValueField(wireName: r'utilization')
  BuiltList<UtilizationCell> get utilization;

  @BuiltValueField(wireName: r'retention')
  BuiltList<RetentionPoint> get retention;

  /// Total bookings in the window.
  @BuiltValueField(wireName: r'total')
  int get total;

  BookingsReport._();

  factory BookingsReport([void updates(BookingsReportBuilder b)]) = _$BookingsReport;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(BookingsReportBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<BookingsReport> get serializer => _$BookingsReportSerializer();
}

class _$BookingsReportSerializer implements PrimitiveSerializer<BookingsReport> {
  @override
  final Iterable<Type> types = const [BookingsReport, _$BookingsReport];

  @override
  final String wireName = r'BookingsReport';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    BookingsReport object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'daily';
    yield serializers.serialize(
      object.daily,
      specifiedType: const FullType(BuiltList, [FullType(DailyCount)]),
    );
    yield r'utilization';
    yield serializers.serialize(
      object.utilization,
      specifiedType: const FullType(BuiltList, [FullType(UtilizationCell)]),
    );
    yield r'retention';
    yield serializers.serialize(
      object.retention,
      specifiedType: const FullType(BuiltList, [FullType(RetentionPoint)]),
    );
    yield r'total';
    yield serializers.serialize(
      object.total,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    BookingsReport object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required BookingsReportBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'daily':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(DailyCount)]),
          ) as BuiltList<DailyCount>;
          result.daily.replace(valueDes);
          break;
        case r'utilization':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(UtilizationCell)]),
          ) as BuiltList<UtilizationCell>;
          result.utilization.replace(valueDes);
          break;
        case r'retention':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(RetentionPoint)]),
          ) as BuiltList<RetentionPoint>;
          result.retention.replace(valueDes);
          break;
        case r'total':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
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
  BookingsReport deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = BookingsReportBuilder();
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

