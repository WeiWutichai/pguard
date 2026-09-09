//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_payment_api/src/model/date.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'export_deduction_request.g.dart';

/// All fields optional; an absent body sweeps the whole unswept backlog. There is deliberately NO per-job tick list — an `OAT` file credits ONE destination, so there is nobody to choose between, and sweeping half a day's cut would leave the rest looking unswept for a reason nobody could reconstruct later. 
///
/// Properties:
/// * [from] - Inclusive first day the job was SETTLED (Thai local day).
/// * [to] - Inclusive last day the job was SETTLED (Thai local day).
/// * [valueDate] - The batch's effective/value date. Omit for \"today in Bangkok, rolled off a weekend\"; set it to schedule a later settlement day or to step over a Thai public holiday (the platform has no holiday calendar). A PAST date is a 400 — SCB rejects a back-dated batch. 
@BuiltValue()
abstract class ExportDeductionRequest implements Built<ExportDeductionRequest, ExportDeductionRequestBuilder> {
  /// Inclusive first day the job was SETTLED (Thai local day).
  @BuiltValueField(wireName: r'from')
  Date? get from;

  /// Inclusive last day the job was SETTLED (Thai local day).
  @BuiltValueField(wireName: r'to')
  Date? get to;

  /// The batch's effective/value date. Omit for \"today in Bangkok, rolled off a weekend\"; set it to schedule a later settlement day or to step over a Thai public holiday (the platform has no holiday calendar). A PAST date is a 400 — SCB rejects a back-dated batch. 
  @BuiltValueField(wireName: r'value_date')
  Date? get valueDate;

  ExportDeductionRequest._();

  factory ExportDeductionRequest([void updates(ExportDeductionRequestBuilder b)]) = _$ExportDeductionRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ExportDeductionRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ExportDeductionRequest> get serializer => _$ExportDeductionRequestSerializer();
}

class _$ExportDeductionRequestSerializer implements PrimitiveSerializer<ExportDeductionRequest> {
  @override
  final Iterable<Type> types = const [ExportDeductionRequest, _$ExportDeductionRequest];

  @override
  final String wireName = r'ExportDeductionRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ExportDeductionRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
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
    ExportDeductionRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ExportDeductionRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
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
  ExportDeductionRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ExportDeductionRequestBuilder();
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

