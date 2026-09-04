//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_payment_api/src/model/date.dart';
import 'package:built_collection/built_collection.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'export_payout_request.g.dart';

/// Optional narrowing of the export run. Omit the body entirely (or leave every field null) to pay the WHOLE unpaid backlog for every payable guard. `guard_ids` is the preview screen's tick list — MANY guards ride one file; guards left out stay unpaid and reappear in the next run (they are not marked paid). `from`/`to` bound the days the jobs were finished. 
///
/// Properties:
/// * [guardIds] - Pay only these guards (1–500). Null = every payable guard in the window.
/// * [from] - Inclusive first day jobs were finished (Thai local day).
/// * [to] - Inclusive last day jobs were finished (Thai local day).
@BuiltValue()
abstract class ExportPayoutRequest implements Built<ExportPayoutRequest, ExportPayoutRequestBuilder> {
  /// Pay only these guards (1–500). Null = every payable guard in the window.
  @BuiltValueField(wireName: r'guard_ids')
  BuiltList<String>? get guardIds;

  /// Inclusive first day jobs were finished (Thai local day).
  @BuiltValueField(wireName: r'from')
  Date? get from;

  /// Inclusive last day jobs were finished (Thai local day).
  @BuiltValueField(wireName: r'to')
  Date? get to;

  ExportPayoutRequest._();

  factory ExportPayoutRequest([void updates(ExportPayoutRequestBuilder b)]) = _$ExportPayoutRequest;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ExportPayoutRequestBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ExportPayoutRequest> get serializer => _$ExportPayoutRequestSerializer();
}

class _$ExportPayoutRequestSerializer implements PrimitiveSerializer<ExportPayoutRequest> {
  @override
  final Iterable<Type> types = const [ExportPayoutRequest, _$ExportPayoutRequest];

  @override
  final String wireName = r'ExportPayoutRequest';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ExportPayoutRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    if (object.guardIds != null) {
      yield r'guard_ids';
      yield serializers.serialize(
        object.guardIds,
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
  }

  @override
  Object serialize(
    Serializers serializers,
    ExportPayoutRequest object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ExportPayoutRequestBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'guard_ids':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(BuiltList, [FullType(String)]),
          ) as BuiltList<String>;
          result.guardIds.replace(valueDes);
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
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ExportPayoutRequest deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ExportPayoutRequestBuilder();
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

