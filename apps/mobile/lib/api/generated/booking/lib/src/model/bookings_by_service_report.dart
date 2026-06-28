//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_collection/built_collection.dart';
import 'package:pguard_booking_api/src/model/service_type_stat.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'bookings_by_service_report.g.dart';

/// BookingsByServiceReport
///
/// Properties:
/// * [items] 
/// * [total] - Σ of all rows' counts (incl. the unspecified bucket).
@BuiltValue()
abstract class BookingsByServiceReport implements Built<BookingsByServiceReport, BookingsByServiceReportBuilder> {
  @BuiltValueField(wireName: r'items')
  BuiltList<ServiceTypeStat> get items;

  /// Σ of all rows' counts (incl. the unspecified bucket).
  @BuiltValueField(wireName: r'total')
  int get total;

  BookingsByServiceReport._();

  factory BookingsByServiceReport([void updates(BookingsByServiceReportBuilder b)]) = _$BookingsByServiceReport;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(BookingsByServiceReportBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<BookingsByServiceReport> get serializer => _$BookingsByServiceReportSerializer();
}

class _$BookingsByServiceReportSerializer implements PrimitiveSerializer<BookingsByServiceReport> {
  @override
  final Iterable<Type> types = const [BookingsByServiceReport, _$BookingsByServiceReport];

  @override
  final String wireName = r'BookingsByServiceReport';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    BookingsByServiceReport object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'items';
    yield serializers.serialize(
      object.items,
      specifiedType: const FullType(BuiltList, [FullType(ServiceTypeStat)]),
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
    BookingsByServiceReport object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required BookingsByServiceReportBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'items':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(ServiceTypeStat)]),
          ) as BuiltList<ServiceTypeStat>;
          result.items.replace(valueDes);
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
  BookingsByServiceReport deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = BookingsByServiceReportBuilder();
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

