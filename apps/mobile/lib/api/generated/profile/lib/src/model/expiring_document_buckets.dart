//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:built_value/built_value.dart';
import 'package:built_value/serializer.dart';

part 'expiring_document_buckets.g.dart';

/// Disjoint urgency-band counts over ALL recorded expiries (window-independent — the dashboard pills don't change as the list filter narrows). Bands by `days_left`: expired (<0), due_7 (0..=7), due_30 (8..=30), due_90 (31..=90). 
///
/// Properties:
/// * [expired] 
/// * [due7] 
/// * [due30] 
/// * [due90] 
@BuiltValue()
abstract class ExpiringDocumentBuckets implements Built<ExpiringDocumentBuckets, ExpiringDocumentBucketsBuilder> {
  @BuiltValueField(wireName: r'expired')
  int get expired;

  @BuiltValueField(wireName: r'due_7')
  int get due7;

  @BuiltValueField(wireName: r'due_30')
  int get due30;

  @BuiltValueField(wireName: r'due_90')
  int get due90;

  ExpiringDocumentBuckets._();

  factory ExpiringDocumentBuckets([void updates(ExpiringDocumentBucketsBuilder b)]) = _$ExpiringDocumentBuckets;

  @BuiltValueHook(initializeBuilder: true)
  static void _defaults(ExpiringDocumentBucketsBuilder b) => b;

  @BuiltValueSerializer(custom: true)
  static Serializer<ExpiringDocumentBuckets> get serializer => _$ExpiringDocumentBucketsSerializer();
}

class _$ExpiringDocumentBucketsSerializer implements PrimitiveSerializer<ExpiringDocumentBuckets> {
  @override
  final Iterable<Type> types = const [ExpiringDocumentBuckets, _$ExpiringDocumentBuckets];

  @override
  final String wireName = r'ExpiringDocumentBuckets';

  Iterable<Object?> _serializeProperties(
    Serializers serializers,
    ExpiringDocumentBuckets object, {
    FullType specifiedType = FullType.unspecified,
  }) sync* {
    yield r'expired';
    yield serializers.serialize(
      object.expired,
      specifiedType: const FullType(int),
    );
    yield r'due_7';
    yield serializers.serialize(
      object.due7,
      specifiedType: const FullType(int),
    );
    yield r'due_30';
    yield serializers.serialize(
      object.due30,
      specifiedType: const FullType(int),
    );
    yield r'due_90';
    yield serializers.serialize(
      object.due90,
      specifiedType: const FullType(int),
    );
  }

  @override
  Object serialize(
    Serializers serializers,
    ExpiringDocumentBuckets object, {
    FullType specifiedType = FullType.unspecified,
  }) {
    return _serializeProperties(serializers, object, specifiedType: specifiedType).toList();
  }

  void _deserializeProperties(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
    required List<Object?> serializedList,
    required ExpiringDocumentBucketsBuilder result,
    required List<Object?> unhandled,
  }) {
    for (var i = 0; i < serializedList.length; i += 2) {
      final key = serializedList[i] as String;
      final value = serializedList[i + 1];
      switch (key) {
        case r'expired':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.expired = valueDes;
          break;
        case r'due_7':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.due7 = valueDes;
          break;
        case r'due_30':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.due30 = valueDes;
          break;
        case r'due_90':
          final valueDes = serializers.deserialize(
            value,
            specifiedType: const FullType(int),
          ) as int;
          result.due90 = valueDes;
          break;
        default:
          unhandled.add(key);
          unhandled.add(value);
          break;
      }
    }
  }

  @override
  ExpiringDocumentBuckets deserialize(
    Serializers serializers,
    Object serialized, {
    FullType specifiedType = FullType.unspecified,
  }) {
    final result = ExpiringDocumentBucketsBuilder();
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

