//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_payment_api/src/model/date.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'export_refund_request.g.dart';

/// Optional narrowing of the refund run. Omit the body entirely (or leave every field null) to refund the WHOLE backlog. `customer_ids` is the preview screen's tick list — MANY customers ride one file; customers left out stay owed and reappear in the next run (they are not marked processed). `from`/`to` bound the days the refunds became owed. 
///
/// Properties:
/// * [customerIds] - Refund only these customers (1–500). Null = every refundable customer in the window.
/// * [from] - Inclusive first day the refund became owed (Thai local day).
/// * [to] - Inclusive last day the refund became owed (Thai local day).
/// * [valueDate] - The batch's effective/value date. Omit for today in Asia/Bangkok rolled forward off a weekend; set it to schedule a later settlement day or to step over a Thai public holiday (the platform has no holiday calendar). A PAST date is a 400 — SCB rejects a back-dated batch outright. 
@BuiltValue()
abstract class ExportRefundRequest implements Built<ExportRefundRequest, ExportRefundRequestBuilder> {
  /// Refund only these customers (1–500). Null = every refundable customer in the window.
  @BuiltValueField(wireName: r'customer_ids')
  BuiltList<String>? get customerIds;

  /// Inclusive first day the refund became owed (Thai local day).
  @BuiltValueField(wireName: r'from')
  Date? get from;

  /// Inclusive last day the refund became owed (Thai local day).
  @BuiltValueField(wireName: r'to')
  Date? get to;

  /// The batch's effective/value date. Omit for today in Asia/Bangkok rolled forward off a weekend; set it to schedule a later settlement day or to step over a Thai public holiday (the platform has no holiday calendar). A PAST date is a 400 — SCB rejects a back-dated batch outright. 
  @BuiltValueField(wireName: r'value_date')
  Date? get valueDate;

  ExportRefundRequest._();

  factory ExportRefundRequest([void updates(ExportRefundRequestBuilder b)]) = _$ExportRefundRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ExportRefundRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ExportRefundRequest> get serializer => _$ExportRefundRequestSerializer();
}

class _$ExportRefundRequestSerializer implements PrimitiveSerializer<ExportRefundRequest> {
  @override
  final Iterable<Type> types = const [ExportRefundRequest, _$ExportRefundRequest];

  @override
  final String wireName = r'ExportRefundRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ExportRefundRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.customerIds != null) {
      yield r'customer_ids';
      yield serializers.serialize(
        object.customerIds,
        specifiedType: const FullType(BuiltList, [FullType(String)]),
      );
    }
    if (object.from != null) {
      yield r'from';
      yield serializers.serialize(
        object.from,
        specifiedType: const FullType(Date),
      );
    }
    if (object.to != null) {
      yield r'to';
      yield serializers.serialize(
        object.to,
        specifiedType: const FullType(Date),
      );
    }
    if (object.valueDate != null) {
      yield r'value_date';
      yield serializers.serialize(
        object.valueDate,
        specifiedType: const FullType(Date),
      );
    }
  }

  @override
  Object serialize(
    Serializers serializers,
    ExportRefundRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ExportRefundRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'customer_ids':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.customerIds.replace(valueDes);
          break;
        case r'from':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(Date),
          ) as Date;
          result.from = valueDes;
          break;
        case r'to':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(Date),
          ) as Date;
          result.to = valueDes;
          break;
        case r'value_date':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(Date),
          ) as Date;
          result.valueDate = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ExportRefundRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ExportRefundRequestBuilder();
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

