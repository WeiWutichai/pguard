//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:pguard_payment_api/src/model/refund_source_kind.dart';
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'refund_source_ref.g.dart';

/// ONE refund obligation, named exactly as the batch drill-down reports it.
///
/// Properties:
/// * [sourceKind] 
/// * [sourceId] - The owing row's id — `payments.id` or `payment_slips.id`, per `source_kind`.
@BuiltValue()
abstract class RefundSourceRef implements Built<RefundSourceRef, RefundSourceRefBuilder> {
  @BuiltValueField(wireName: r'source_kind')
  RefundSourceKind get sourceKind;
  // enum sourceKindEnum {  payment,  slip,  };

  /// The owing row's id — `payments.id` or `payment_slips.id`, per `source_kind`.
  @BuiltValueField(wireName: r'source_id')
  String get sourceId;

  RefundSourceRef._();

  factory RefundSourceRef([void updates(RefundSourceRefBuilder b)]) = _$RefundSourceRef;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(RefundSourceRefBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<RefundSourceRef> get serializer => _$RefundSourceRefSerializer();
}

class _$RefundSourceRefSerializer implements PrimitiveSerializer<RefundSourceRef> {
  @override
  final Iterable<Type> types = const [RefundSourceRef, _$RefundSourceRef];

  @override
  final String wireName = r'RefundSourceRef';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    RefundSourceRef object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'source_kind';
    yield serializers.serialize(
      object.sourceKind,
      specifiedType: const FullType(RefundSourceKind),
    );
    yield r'source_id';
    yield serializers.serialize(
      object.sourceId,
      specifiedType: const FullType(String),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    RefundSourceRef object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required RefundSourceRefBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'source_kind':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(RefundSourceKind),
          ) as RefundSourceKind;
          result.sourceKind = valueDes;
          break;
        case r'source_id':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(String),
          ) as String;
          result.sourceId = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  RefundSourceRef deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = RefundSourceRefBuilder();
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

